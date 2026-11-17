import AppKit
import Carbon
import FloatCore
import OSLog
import QuartzCore
import SwiftUI

@MainActor
private final class FloatApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let panelWidth: CGFloat = 516
    private let logger = Logger(subsystem: "com.dylyoung.float", category: "panel")
    private let chat: ChatState
    private let sizing: PanelSizing
    private var panel: FloatPanel?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var desiredHeight: CGFloat = 79
    private var trayVisible: Bool?
    private var positioned = false
    private var shuttingDown = false

    override init() {
        let env = ProcessInfo.processInfo.environment
        let client = T3Client(
            base: env["FLOAT_T3_BASE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            executable: env["FLOAT_T3_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
        )
        chat = ChatState(client: client)
        sizing = PanelSizing(visibleScreenHeight: NSScreen.main?.visibleFrame.height ?? 1_000)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installHotkey()
        installMenu()
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
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            if panel.screen != screen { positioned = false }
            layout(on: screen)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        chat.revealed()
        logger.info("Opened panel \(panel.windowNumber) (visible \(panel.isVisible), level \(panel.level.rawValue))")
    }

    private func hide() {
        panel?.orderOut(nil)
        logger.info("Hid panel")
        chat.hidden()
    }

    private func makePanel() -> FloatPanel {
        let panel = FloatPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: desiredHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Float"
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
        panel.openModelPicker = { [weak self] in self?.chat.requestModelPicker() }
        panel.stopRun = { [weak self] in self?.chat.stop() }
        let host = NSHostingView(rootView: FloatView(chat: chat, sizing: sizing, resize: {
            [weak self] height, trayVisible, resizing in
            // SwiftUI may update its preferred size while the window is laying out.
            DispatchQueue.main.async {
                self?.resize(to: height, trayVisible: trayVisible, resizing: resizing)
            }
        }, dismiss: { [weak self] in self?.hide() }))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func resize(to height: CGFloat, trayVisible: Bool, resizing: Bool) {
        let animate = (self.trayVisible.map { $0 != trayVisible } ?? false) && !resizing
        self.trayVisible = trayVisible
        guard height != desiredHeight else { return }
        desiredHeight = height
        if let screen = panel?.screen ?? NSScreen.main {
            layout(on: screen, animated: animate, preservingBottom: resizing)
        }
    }

    private func layout(on screen: NSScreen, animated: Bool = false, preservingBottom: Bool = false) {
        guard let panel else { return }
        sizing.updateVisibleScreenHeight(screen.visibleFrame.height)
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let width = min(Self.panelWidth, visible.width)
        let height = min(desiredHeight, visible.height)
        let x = positioned ? panel.frame.minX : visible.midX - width / 2
        let proposedBottom = positioned ? panel.frame.minY : visible.midY + visible.height * 0.10
        let bottom = preservingBottom && positioned
            ? proposedBottom
            : min(max(proposedBottom, visible.minY), visible.maxY - height)
        let rect = NSRect(
            x: min(max(x, visible.minX), visible.maxX - width),
            y: bottom,
            width: width, height: height
        )
        if animated, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(rect, display: true)
            }
        } else {
            panel.setFrame(rect, display: true)
        }
        positioned = true
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let screen = panel?.screen else { return }
        sizing.updateVisibleScreenHeight(screen.visibleFrame.height)
        layout(on: screen)
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = .floatCloud()
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
            let bottom = button.isFlipped ? button.bounds.maxY : button.bounds.minY
            statusMenu?.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: bottom), in: button)
        } else {
            toggle()
        }
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
