import AppKit
import FloatCore
import SwiftUI

struct MachineMenuAnchor: NSViewRepresentable {
    let chat: ChatState
    let request: Int
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> Anchor { Anchor(request: request) }

    func updateNSView(_ anchor: Anchor, context: Context) {
        guard anchor.request != request else { return }
        anchor.request = request
        DispatchQueue.main.async { [weak anchor, weak chat] in
            guard let anchor, let chat, anchor.request == request, chat.canChooseMachine,
                anchor.window?.isKeyWindow == true
            else { return }
            anchor.showMenu(for: chat, isPresented: $isPresented)
        }
    }

    static func dismantleNSView(_ anchor: Anchor, coordinator: ()) {
        DispatchQueue.main.async { anchor.closePicker() }
    }

    final class Anchor: NSView {
        var request: Int
        private var picker: MachinePickerPanelController?

        init(request: Int) {
            self.request = request
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func closePicker() { picker?.close() }

        func showMenu(for chat: ChatState, isPresented: Binding<Bool>) {
            closePicker()
            guard let window else { return }
            let controller = MachinePickerPanelController(anchor: self, parent: window, chat: chat)
            picker = controller
            controller.show { [weak self] in
                self?.picker = nil
                isPresented.wrappedValue = false
            }
            isPresented.wrappedValue = true
        }
    }
}

@MainActor
private final class MachinePickerPanelController {
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private weak var chat: ChatState?
    private let panel: PickerPanel
    private let keyboard = MachinePickerKeyboard()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onClose: (() -> Void)?

    init(anchor: NSView, parent: NSWindow, chat: ChatState) {
        self.anchor = anchor
        self.parent = parent
        self.chat = chat
        panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 236, height: 160),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.dismiss = { [weak self] in self?.close() }
        panel.handleKey = { [weak self] in self?.handleKey($0) == true }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    }

    func show(onClose: @escaping () -> Void) {
        guard let anchor, let parent, let chat else { return }
        self.onClose = onClose
        let height = min(320, CGFloat(71 + chat.machines.count * 42))
        let host = NSHostingView(rootView: MachinePickerView(
            chat: chat, keyboard: keyboard, close: { [weak self] in self?.close() }
        ))
        host.sizingOptions = []
        panel.contentView = host
        let anchorFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: anchorFrame.minX, y: anchorFrame.maxY + 6)
        origin.x = min(max(visible.minX + 6, origin.x), visible.maxX - 242)
        if origin.y + height > visible.maxY {
            origin.y = anchorFrame.minY - height - 6
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: 236, height: height), display: true)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        // Keep arrow navigation active without focusing the footer on open.
        panel.makeFirstResponder(nil)
        installMonitors()
    }

    func close() {
        guard onClose != nil else { return }
        removeMonitors()
        if let parent {
            parent.removeChildWindow(panel)
            parent.makeKeyAndOrderFront(nil)
        }
        panel.orderOut(nil)
        chat?.restoreComposerFocus()
        let completion = onClose
        onClose = nil
        completion?()
    }

    private func installMonitors() {
        // Keys go through the picker panel's own sendEvent (`handleKey`), as in the model
        // picker. An app-wide key monitor misses them when Float isn't the active app.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window !== panel { close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.close() }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 125: keyboard.send(.move(1))
        case 126: keyboard.send(.move(-1))
        case 36, 76: keyboard.send(.pick)
        default: return false
        }
        return true
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

@MainActor
private final class MachinePickerKeyboard: ObservableObject {
    enum Command { case move(Int), pick }
    struct Event {
        let id = UUID()
        let command: Command
    }

    @Published private(set) var event: Event?

    func send(_ command: Command) { event = Event(command: command) }
}

private struct MachinePickerView: View {
    @ObservedObject var chat: ChatState
    @ObservedObject var keyboard: MachinePickerKeyboard
    let close: () -> Void

    @State private var hoveredID: String?
    @State private var highlightedID: String?

    init(chat: ChatState, keyboard: MachinePickerKeyboard, close: @escaping () -> Void) {
        self.chat = chat
        self.keyboard = keyboard
        self.close = close
    }

    private var choices: [T3Machine] { chat.machines.filter(\.isOnline) }

    var body: some View {
        VStack(spacing: 0) {
            Text("Run on")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 25, alignment: .bottom)
                .padding(.bottom, 3)
            // Follow the keyboard highlight: scroll just far enough to keep it in view.
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(chat.machines) { machine in machineRow(machine) }
                    }
                    .background(OverlayScrollers())
                }
                .flashScrollKnobsOnHover()
                .onChange(of: highlightedID) {
                    if let highlightedID { scroll.scrollTo(highlightedID) }
                }
            }
            Divider().overlay(Theme.border)
                .padding(.horizontal, 2)
                .padding(.top, 3)
            Button {
                chat.openMachineSettings()
                close()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("Link machines in T3")
                        .font(.system(size: 10.5))
                    Spacer()
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .floatButtonStyle()
        }
        .padding(4)
        .frame(width: 236)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .onExitCommand(perform: close)
        .onChange(of: keyboard.event?.id) {
            if let command = keyboard.event?.command { handle(command) }
        }
    }

    private func machineRow(_ machine: T3Machine) -> some View {
        let current = machine.id == chat.selectedMachine?.id
        return HStack(spacing: 8) {
            Image(systemName: machine.isLocal ? "laptopcomputer" : "server.rack")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name)
                    .font(.system(size: 12))
                    .foregroundStyle(machine.isOnline ? Theme.text : Theme.muted)
                    .lineLimit(1)
                Text(subtitle(machine))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Circle()
                .fill(machine.isOnline ? Theme.success : Theme.muted)
                .frame(width: 6, height: 6)

        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(
            machine.isOnline && (highlightedID == machine.id || hoveredID == machine.id) ? Theme.text.opacity(0.06) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .background(current ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .id(machine.id)
        .onHover { hoveredID = $0 && machine.isOnline ? machine.id : nil }
        .onTapGesture {
            guard machine.isOnline else { return }
            chat.selectMachine(machine)
            close()
        }
    }

    private func subtitle(_ machine: T3Machine) -> String {
        if machine.isLocal { return "client · \(NSFullUserName())" }
        guard machine.isOnline else { return "Offline" }
        if let count = machine.projectCount {
            return "Linked · \(count) project\(count == 1 ? "" : "s")"
        }
        return "Linked"
    }

    private func handle(_ command: MachinePickerKeyboard.Command) {
        guard !choices.isEmpty else { return }
        let selectedID = highlightedID ?? chat.selectedMachine?.id
        switch command {
        case .move(let direction):
            hoveredID = nil
            let current = choices.firstIndex { $0.id == selectedID }
            let index = current.map { ($0 + direction + choices.count) % choices.count }
                ?? (direction > 0 ? 0 : choices.count - 1)
            highlightedID = choices[index].id
        case .pick:
            guard let machine = choices.first(where: { $0.id == (hoveredID ?? selectedID) }) else { return }
            chat.selectMachine(machine)
            close()
        }
    }
}
