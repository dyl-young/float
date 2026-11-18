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

private final class ProjectPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class ProjectPickerPanelController {
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private weak var chat: ChatState?
    private let panel: ProjectPickerPanel
    private let keyboard = ProjectPickerKeyboard()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onClose: (() -> Void)?
    private var anchorFrame = NSRect.zero
    private var visibleFrame = NSRect.zero

    init(anchor: NSView, parent: NSWindow, chat: ChatState) {
        self.anchor = anchor
        self.parent = parent
        self.chat = chat
        panel = ProjectPickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 180),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    }

    func show(onClose: @escaping () -> Void) {
        guard let anchor, let parent, let chat else { return }
        self.onClose = onClose
        panel.contentView = NSHostingView(rootView: ProjectPickerView(
            chat: chat, keyboard: keyboard,
            resize: { [weak self] height in self?.resize(to: height) },
            close: { [weak self] in self?.close() }
        ))
        anchorFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        resize(to: panel.frame.height)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() {
        guard panel.isVisible else { return }
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

    private func resize(to height: CGFloat) {
        let height = min(320, max(112, ceil(height)))
        var origin = NSPoint(x: anchorFrame.minX, y: anchorFrame.maxY + 6)
        origin.x = min(max(visibleFrame.minX + 6, origin.x), visibleFrame.maxX - 256)
        if origin.y + height > visibleFrame.maxY {
            origin.y = anchorFrame.minY - height - 6
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: 250, height: height), display: true)
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                close()
                return nil
            }
            if event.type == .keyDown {
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
    let resize: (CGFloat) -> Void
    let close: () -> Void

    @State private var search = ""
    @State private var highlightedID: String
    @FocusState private var searchFocused: Bool

    init(
        chat: ChatState, keyboard: ProjectPickerKeyboard,
        resize: @escaping (CGFloat) -> Void, close: @escaping () -> Void
    ) {
        self.chat = chat
        self.keyboard = keyboard
        self.resize = resize
        self.close = close
        _highlightedID = State(initialValue: chat.selectedProject?.id ?? Self.scratch)
    }

    private var filteredProjects: [T3Project] {
        T3ProjectSearch.filter(chat.projects, query: search)
    }

    private var choiceIDs: [String] {
        [Self.scratch] + filteredProjects.map(\.id)
    }

    private var listHeight: CGFloat {
        let rows = 40 + CGFloat(filteredProjects.count * 38)
            + (chat.loadingProjects || chat.projectCatalogFailed ? 38 : 0)
        return min(228, max(40, rows))
    }

    private var pickerHeight: CGFloat { 8 + 32 + listHeight + 1 + 28 }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            projectList.frame(height: listHeight)
            Divider().overlay(Theme.border)
            hintRow
        }
        .padding(4)
        .frame(width: 250, height: pickerHeight, alignment: .top)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            searchFocused = true
            resize(pickerHeight)
        }
        .onExitCommand(perform: close)
        .onChange(of: search) {
            highlightedID = choiceIDs.first ?? Self.scratch
        }
        .onChange(of: keyboard.event?.id) {
            if let command = keyboard.event?.command { handle(command) }
        }
        .onChange(of: pickerHeight) { resize(pickerHeight) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("Search projects", text: $search)
                .textFieldStyle(.plain)
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
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                }
            }
        }
        .scrollIndicators(.visible)
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
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(highlightedID == id ? Theme.text.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { if $0 { highlightedID = id } }
        .onTapGesture {
            chat.selectProject(project)
            close()
        }
    }

    private var hintRow: some View {
        HStack(spacing: 6) {
            keyCap("↑↓")
            Text("move")
            keyCap("↵")
            Text("pick")
            Spacer()
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
        .frame(height: 28)
    }

    private func keyCap(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 4)
            .frame(height: 18)
            .background(Theme.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    private func handle(_ command: ProjectPickerKeyboard.Command) {
        switch command {
        case .move(let direction):
            guard !choiceIDs.isEmpty else { return }
            let current = choiceIDs.firstIndex(of: highlightedID)
            let index = current.map { ($0 + direction + choiceIDs.count) % choiceIDs.count }
                ?? (direction > 0 ? 0 : choiceIDs.count - 1)
            highlightedID = choiceIDs[index]
        case .pick:
            let project = filteredProjects.first { $0.id == highlightedID }
            chat.selectProject(project)
            close()
        }
    }
}
