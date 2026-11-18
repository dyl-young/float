import AppKit
import FloatCore
import SwiftUI

struct ProjectMenuAnchor: NSViewRepresentable {
    let chat: ChatState
    let request: Int

    func makeNSView(context: Context) -> Anchor { Anchor(request: request) }

    func updateNSView(_ anchor: Anchor, context: Context) {
        guard anchor.request != request else { return }
        anchor.request = request
        DispatchQueue.main.async { [weak anchor, weak chat] in
            guard let anchor, let chat, anchor.request == request, chat.canChooseProject,
                anchor.window?.isKeyWindow == true
            else { return }
            anchor.showMenu(for: chat)
        }
    }

    final class Anchor: NSView {
        var request: Int
        private var picker: ProjectPickerPanelController?

        init(request: Int) {
            self.request = request
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func showMenu(for chat: ChatState) {
            picker?.close()
            guard let window else { return }
            let controller = ProjectPickerPanelController(anchor: self, parent: window, chat: chat)
            picker = controller
            controller.show { [weak self] in self?.picker = nil }
        }
    }
}

@MainActor
private final class ProjectPickerPanelController {
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private weak var chat: ChatState?
    private let panel: PickerPanel
    private let keyboard = ProjectPickerKeyboard()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onClose: (() -> Void)?

    init(anchor: NSView, parent: NSWindow, chat: ChatState) {
        self.anchor = anchor
        self.parent = parent
        self.chat = chat
        panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 180),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.dismiss = { [weak self] in self?.close() }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    }

    func show(onClose: @escaping () -> Void) {
        guard let anchor, let parent, let chat else { return }
        self.onClose = onClose
        let rows = 65 + CGFloat(chat.projects.count * 38)
            + (chat.loadingProjects || chat.projectCatalogFailed ? 38 : 0)
        let height = 42 + min(228, rows)
        let host = NSHostingView(rootView: ProjectPickerView(
            chat: chat, keyboard: keyboard, height: height, close: { [weak self] in self?.close() }
        ))
        host.sizingOptions = []
        panel.contentView = host

        let anchorFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: anchorFrame.minX, y: anchorFrame.maxY + 6)
        origin.x = min(max(visibleFrame.minX + 6, origin.x), visibleFrame.maxX - 256)
        if origin.y + height > visibleFrame.maxY {
            origin.y = anchorFrame.minY - height - 6
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: 250, height: height)), display: true)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
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
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === panel,
               (panel.firstResponder as? NSTextView)?.hasMarkedText() != true {
                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                if modifiers.isEmpty {
                    switch event.keyCode {
                    case 125: keyboard.send(.move(1)); return nil
                    case 126: keyboard.send(.move(-1)); return nil
                    case 36, 76: keyboard.send(.pick); return nil
                    default: break
                    }
                }
            }
            if event.type != .keyDown, event.window !== panel { close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.close() }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

@MainActor
private final class ProjectPickerKeyboard: ObservableObject {
    enum Command { case move(Int), pick }
    struct Event {
        let id = UUID()
        let command: Command
    }

    @Published private(set) var event: Event?

    func send(_ command: Command) {
        event = Event(command: command)
    }
}

private struct ProjectPickerView: View {
    private static let scratch = "__float_no_project__"

    @ObservedObject var chat: ChatState
    @ObservedObject var keyboard: ProjectPickerKeyboard
    let height: CGFloat
    let close: () -> Void

    @State private var search = ""
    @State private var hoveredID: String?
    @State private var highlightedID: String?
    @FocusState private var searchFocused: Bool

    init(
        chat: ChatState, keyboard: ProjectPickerKeyboard,
        height: CGFloat, close: @escaping () -> Void
    ) {
        self.chat = chat
        self.keyboard = keyboard
        self.height = height
        self.close = close
    }

    private var filteredProjects: [T3Project] {
        T3ProjectSearch.filter(chat.projects, query: search)
    }

    private var choiceIDs: [String] {
        [Self.scratch] + filteredProjects.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            projectList.frame(maxHeight: .infinity)
        }
        .padding(4)
        .frame(width: 250, height: height, alignment: .top)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .defaultFocus($searchFocused, true)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: close)
        .onChange(of: search) {
            highlightedID = choiceIDs.first ?? Self.scratch
        }
        .onChange(of: keyboard.event?.id) {
            if let command = keyboard.event?.command { handle(command) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("Search projects", text: $search)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(2)
        .padding(.bottom, 2)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                projectRow(id: Self.scratch, title: "No project", subtitle: "Scratch chat, no repo")
                Text("On \(chat.machineLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 23, alignment: .bottom)
                    .padding(.bottom, 2)
                ForEach(filteredProjects) { project in
                    projectRow(
                        id: project.id, title: project.title,
                        subtitle: project.shortenedPath(), project: project
                    )
                }
                if chat.loadingProjects {
                    Text("Loading projects…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                } else if chat.projectCatalogFailed {
                    HStack(spacing: 8) {
                        Text("Couldn't load projects")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Retry", action: chat.reloadProjects)
                            .floatButtonStyle()
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                }
            }
            .background(OverlayScrollers())
        }
        .flashScrollKnobsOnHover()
    }

    private func projectRow(
        id: String, title: String, subtitle: String, project: T3Project? = nil
    ) -> some View {
        let currentProjectID = chat.selectedProject?.id
        let isCurrent = project?.id == currentProjectID
            || (project == nil && currentProjectID == nil)
        return HStack(spacing: 8) {
            Image(systemName: project == nil ? "pencil" : "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            (highlightedID == id || hoveredID == id) ? Theme.text.opacity(0.06) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .background(isCurrent ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? id : nil }
        .onTapGesture {
            chat.selectProject(project)
            close()
        }
    }

    private func handle(_ command: ProjectPickerKeyboard.Command) {
        let selectedID = highlightedID ?? chat.selectedProject?.id ?? Self.scratch
        switch command {
        case .move(let direction):
            hoveredID = nil
            guard !choiceIDs.isEmpty else { return }
            let current = choiceIDs.firstIndex(of: selectedID)
            let index = current.map { ($0 + direction + choiceIDs.count) % choiceIDs.count }
                ?? (direction > 0 ? 0 : choiceIDs.count - 1)
            highlightedID = choiceIDs[index]
        case .pick:
            let project = filteredProjects.first { $0.id == (hoveredID ?? selectedID) }
            chat.selectProject(project)
            close()
        }
    }
}
