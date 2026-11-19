import AppKit
import Carbon
import FloatCore
import OSLog
import QuartzCore
import SwiftUI

@MainActor
private final class FloatApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(subsystem: "com.dylyoung.float", category: "panel")
    private let chat: ChatState
    private let sizing: PanelSizing
    private var panel: FloatPanel?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var approvalMenuItem: NSMenuItem?
    private var screenSharingMenuItem: NSMenuItem?
    /// Remembered across launches (on by default). `FLOAT_ALLOW_CAPTURE=1` turns it off for one
    /// launch without changing the saved choice, so QA screenshots work.
    private static let hideFromScreenSharingKey = "hideFromScreenSharing"
    private let captureOverride = ProcessInfo.processInfo.environment["FLOAT_ALLOW_CAPTURE"] == "1"
    private lazy var hideFromScreenSharing: Bool = !captureOverride
        && (preferences.object(forKey: Self.hideFromScreenSharingKey) as? Bool ?? true)
    private let preferences = UserDefaults(suiteName: PanelSizing.defaultsDomain) ?? .standard
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var compactHeight: CGFloat = 86 + FloatView.contextRowHeight
    private var trayVisible = false
    private var positioned = false
    private var shuttingDown = false
    /// The app that was frontmost before Float was summoned, to hand focus back on hide.
    private var previousApp: NSRunningApplication?


    override init() {
        let env = ProcessInfo.processInfo.environment
        let client = T3Client(
            base: env["FLOAT_T3_BASE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            executable: env["FLOAT_T3_EXECUTABLE"].map { URL(fileURLWithPath: $0) },
            desktopApp: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.t3tools.t3code")
        )
        chat = ChatState(client: client)
        sizing = PanelSizing()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installHotkey()
        installMenu()
        chat.startApprovalMaintenance()
        show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shuttingDown { return .terminateNow }
        shuttingDown = true
        Task {
            await chat.close()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        let pointer = NSEvent.mouseLocation
        if !trayVisible || !positioned,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            if panel.screen != screen { positioned = false }
            layout(on: screen)
        }
        // Activate while shown so window managers (Raycast, Rectangle) see Float as the
        // frontmost app and act on its panel rather than the window behind it.
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        chat.revealed()
        logger.info("Opened panel \(panel.windowNumber) (visible \(panel.isVisible), level \(panel.level.rawValue))")
    }

    private func hide() {
        _ = panel?.closePicker()
        panel?.orderOut(nil)
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
        logger.info("Hid panel")
        chat.hidden()
    }

    private func closeChat() {
        chat.newChat()
        hide()
    }

    private func makePanel() -> FloatPanel {
        let panel = FloatPanel(
            contentRect: NSRect(x: 0, y: 0, width: sizing.width + 2 * FloatView.contextShadowSides, height: compactHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Float"
        panel.setScreenSharingHidden(hideFromScreenSharing)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        panel.dismiss = { [weak self] in self?.hide() }
        panel.startNewChat = { [weak self] in self?.chat.newChat() }
        panel.openChatSwitcher = { [weak self] in self?.chat.requestChatSwitcher() }
        panel.openModelPicker = { [weak self] in self?.chat.requestModelPicker() }
        panel.openProjectPicker = { [weak self] in self?.chat.requestProjectPicker() }
        panel.openMachinePicker = { [weak self] in self?.chat.requestMachinePicker() }
        panel.stopRun = { [weak self] in self?.chat.stop() }
        panel.allowApproval = { [weak self] in self?.chat.allowVisibleApproval() ?? false }
        panel.goBackQuestion = { [weak self] in self?.chat.goBackQuestion() ?? false }
        panel.closeQuestionSteps = { [weak self] in self?.chat.closeQuestionSteps() ?? false }
        panel.sizing = sizing
        panel.adoptAccessibilitySize = { [weak self] size in self?.adoptAccessibilitySize(size) }
        let host = FloatPanelHostingView(rootView: FloatView(chat: chat, resize: {
            [weak self] height, trayVisible in
            // SwiftUI may update its preferred size while the window is laying out.
            DispatchQueue.main.async {
                self?.resize(to: height, trayVisible: trayVisible)
            }
        }, close: { [weak self] in self?.closeChat() }))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func resize(to height: CGFloat, trayVisible: Bool) {
        let animate = self.trayVisible != trayVisible
        guard animate || (!trayVisible && height != compactHeight) else { return }
        let previousTrayVisible = self.trayVisible
        self.trayVisible = trayVisible
        if !trayVisible { compactHeight = height }
        panel?.resizeEnabled = trayVisible
        if let screen = panel?.screen ?? NSScreen.main {
            layout(on: screen, animated: animate, previousTrayVisible: previousTrayVisible)
        }
    }

    private func layout(
        on screen: NSScreen, animated: Bool = false, previousTrayVisible: Bool? = nil
    ) {
        guard let panel, !panel.isResizing else { return }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let trayHeight = sizing.height(on: screen.visibleFrame.height)
        let sideInset = trayVisible ? 0 : FloatView.contextShadowSides
        let bottomInset = trayVisible ? 0 : FloatView.contextRowHeight
        let wasExpanded = previousTrayVisible ?? trayVisible
        let previousSideInset = wasExpanded ? 0 : FloatView.contextShadowSides
        let previousBottomInset = wasExpanded ? 0 : FloatView.contextRowHeight
        let width = min(sizing.width + 2 * sideInset, visible.width)
        let height = min(trayVisible ? trayHeight : compactHeight, visible.height)
        // Anchor the composer itself as the strip's transparent window margins come and go.
        let x = positioned ? panel.frame.minX + previousSideInset - sideInset : visible.midX - width / 2
        let proposedBottom = positioned ? panel.frame.minY + previousBottomInset - bottomInset
            : min(visible.midY + visible.height * 0.10, visible.maxY - trayHeight) - bottomInset
        let bottom = min(max(proposedBottom, visible.minY), visible.maxY - height)
        let rect = NSRect(
            x: min(max(x, visible.minX), visible.maxX - width),
            y: bottom,
            width: width, height: height
        )
        // Route each frame through the animator so a new measurement can
        // supersede a pending tray transition.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && panel.isVisible ? 0.18 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(rect, display: true)
        }
        positioned = true
    }

    /// A window manager (Raycast, Rectangle) asked for a new size through Accessibility. Keep it
    /// within Float's limits, keep the top-left where the manager put it, and remember the size
    /// so the next layout doesn't snap it back. The compact state keeps its own height.
    private func adoptAccessibilitySize(_ requested: NSSize) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let sideInset = trayVisible ? 0 : FloatView.contextShadowSides
        let width = CGFloat(PanelWidthLimits.clamp(Double(requested.width - 2 * sideInset)))
        let height: CGFloat
        if trayVisible {
            height = sizing.clampHeight(Double(requested.height), on: screen.visibleFrame.height)
            sizing.save(CGSize(width: width, height: height))
        } else {
            height = min(compactHeight, screen.visibleFrame.height)
            sizing.saveWidth(width)
        }
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: width + 2 * sideInset, height: height),
            display: true
        )
        positioned = true
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard !trayVisible, let screen = panel?.screen else { return }
        layout(on: screen)
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = .floatCloud()
        item.button?.focusRingType = .none
        item.button?.toolTip = hotKey == nil ? "Float · ⌥Space is unavailable" : "Float · ⌥Space"

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show or Hide Float", action: #selector(toggle), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        if hotKey == nil {
            let unavailable = NSMenuItem(title: "⌥Space is used by another app", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            menu.addItem(unavailable)
        }
        menu.addItem(.separator())
        let approvals = NSMenuItem(title: "Answer approvals in Float", action: #selector(toggleApprovals), keyEquivalent: "")
        approvals.target = self
        menu.addItem(approvals)
        approvalMenuItem = approvals
        let screenSharing = NSMenuItem(
            title: "Hide from screen sharing", action: #selector(toggleScreenSharing), keyEquivalent: ""
        )
        screenSharing.target = self
        screenSharing.state = hideFromScreenSharing ? .on : .off
        menu.addItem(screenSharing)
        screenSharingMenuItem = screenSharing
        menu.addItem(withTitle: "Quit Float", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        statusMenu = menu
    }

    @objc private func statusItemClicked(_ button: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            approvalMenuItem?.state = chat.approvalAccessEnabled ? .on : .off
            let bottom = button.isFlipped ? button.bounds.maxY : button.bounds.minY
            statusMenu?.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: bottom), in: button)
        } else {
            toggle()
        }
    }

    @objc private func toggleApprovals() {
        guard !chat.approvalAccessBusy else { return }
        if chat.approvalAccessEnabled {
            chat.disableApprovals()
        } else {
            show()
        }
    }

    @objc private func toggleScreenSharing() {
        hideFromScreenSharing.toggle()
        preferences.set(hideFromScreenSharing, forKey: Self.hideFromScreenSharingKey)
        panel?.setScreenSharingHidden(hideFromScreenSharing)
        screenSharingMenuItem?.state = hideFromScreenSharing ? .on : .off
    }

    private func installHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<FloatApp>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { app.toggle() }
            return noErr
        }, 1, &eventType, context, &hotKeyHandler)
        guard handlerStatus == noErr else { return }
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(optionKey),
            EventHotKeyID(signature: 0x464C4F54, id: 1), GetApplicationEventTarget(), 0, &hotKey
        )
        logger.info("Global shortcut registration returned \(hotKeyStatus)")
        if hotKeyStatus != noErr, let handler = hotKeyHandler {
            RemoveEventHandler(handler)
            hotKeyHandler = nil
            hotKey = nil
        }
    }
}

let app = NSApplication.shared
private let delegate = FloatApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
withExtendedLifetime(delegate) { app.run() }
