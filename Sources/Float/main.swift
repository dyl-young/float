import AppKit
import Carbon
import FloatCore
import OSLog
import SwiftUI

@MainActor
private final class FloatPanel: NSPanel {
    var dismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { dismiss?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            dismiss?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class FloatApp: NSObject, NSApplicationDelegate {
    private static let panelWidth: CGFloat = 516
    private let logger = Logger(subsystem: "com.dylyoung.float", category: "panel")
    private let chat: ChatState
    private var panel: FloatPanel?
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var screenNumber: NSNumber?
    private var desiredHeight: CGFloat = 79
    private var positioned = false
    private var shuttingDown = false

    override init() {
        let env = ProcessInfo.processInfo.environment
        let client = T3Client(
            base: env["FLOAT_T3_BASE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            executable: env["FLOAT_T3_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
        )
        chat = ChatState(client: client)
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
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            if screenNumber != id { positioned = false }
            screenNumber = id
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
        panel.dismiss = { [weak self] in self?.hide() }
        let host = NSHostingView(rootView: FloatView(chat: chat, resize: { [weak self] height in
            // SwiftUI may update its preferred size while the window is laying out.
            DispatchQueue.main.async { self?.resize(to: height) }
        }))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func resize(to height: CGFloat) {
        guard height != desiredHeight else { return }
        desiredHeight = height
        if let screen = panel?.screen ?? NSScreen.main { layout(on: screen) }
    }

    private func layout(on screen: NSScreen) {
        guard let panel else { return }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let width = min(Self.panelWidth, visible.width)
        let height = min(desiredHeight, visible.height)
        let x = positioned ? panel.frame.minX : visible.midX - width / 2
        let top = positioned ? panel.frame.maxY : visible.maxY - min(115, visible.height / 6)
        let rect = NSRect(
            x: min(max(x, visible.minX), visible.maxX - width),
            y: min(max(top - height, visible.minY), visible.maxY - height),
            width: width, height: height
        )
        panel.setFrame(rect, display: true)
        positioned = true
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Float")
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
        item.menu = menu
        statusItem = item
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
