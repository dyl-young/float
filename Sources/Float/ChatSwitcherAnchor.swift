import AppKit
import FloatCore
import SwiftUI

struct ChatSwitcherAnchor: NSViewRepresentable {
    let chat: ChatState
    let request: Int
    let compact: Bool
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> Anchor { Anchor(request: request) }

    func updateNSView(_ anchor: Anchor, context: Context) {
        guard anchor.request != request else { return }
        anchor.request = request
        DispatchQueue.main.async { [weak anchor, weak chat] in
            guard let anchor, let chat, anchor.request == request,
                  let parent = anchor.window, parent.isKeyWindow else { return }
            anchor.show(for: chat, parent: parent, compact: compact, isPresented: $isPresented)
        }
    }

    static func dismantleNSView(_ anchor: Anchor, coordinator: ()) {
        DispatchQueue.main.async { anchor.close() }
    }

    final class Anchor: NSView {
        var request: Int
        private var picker: ChatSwitcherPanelController?

        init(request: Int) {
            self.request = request
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func close() { picker?.close() }

        func show(for chat: ChatState, parent: NSWindow, compact: Bool, isPresented: Binding<Bool>) {
            close()
            let controller = ChatSwitcherPanelController(anchor: self, parent: parent, chat: chat)
            picker = controller
            isPresented.wrappedValue = true
            controller.show(above: compact) { [weak self] in
                self?.picker = nil
                isPresented.wrappedValue = false
            }
        }
    }
}

@MainActor
private final class ChatSwitcherPanelController {
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private weak var chat: ChatState?
    private let keyboard = ChatSwitcherKeyboard()
    private let panel = PickerPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
    )
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onClose: (() -> Void)?

    init(anchor: NSView, parent: NSWindow, chat: ChatState) {
        self.anchor = anchor
        self.parent = parent
        self.chat = chat
        panel.isChatSwitcher = true
        panel.dismiss = { [weak self] in self?.close() }
        panel.handleKey = { [weak self] in self?.handleKey($0) == true }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    }

    func show(above: Bool, onClose: @escaping () -> Void) {
        guard let anchor, let parent, let chat else { return }
        self.onClose = onClose
        let width: CGFloat = 320
        let groups = chat.chatSwitcherCatalog?.groups
        let rows = groups?.reduce(0) { $0 + $1.entries.count } ?? 0
        let height = rows == 0 ? 360 : min(360, CGFloat(42 + 21 * (groups?.count ?? 0) + 36 * rows))
        let host = NSHostingView(rootView: ChatSwitcherView(chat: chat, keyboard: keyboard, height: height) {
            [weak self, weak chat] entry in
            self?.close()
            chat?.resume(entry)
        }.environment(\.projectFaviconCache, chat.projectFaviconCache))
        host.sizingOptions = []
        panel.contentView = host

        let crumb = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        let x = min(max(screen.minX + 6, crumb.minX), screen.maxX - width - 6)
        let idealY = above ? crumb.maxY + 6 : crumb.minY - height - 6
        let y = min(max(screen.minY + 6, idealY), screen.maxY - height - 6)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        installMonitors(toggleFromCrumb: !above)
    }

    func close() {
        guard let onClose else { return }
        self.onClose = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
        chat?.restoreComposerFocus()
        onClose()
    }

    private func installMonitors(toggleFromCrumb: Bool) {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, event.window !== panel else { return event }
            let clickedCrumb = toggleFromCrumb && event.type == .leftMouseDown && event.window === parent
                && anchor.map { $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } == true
            close()
            return clickedCrumb ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.close() }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 125: keyboard.send(.move(1))
        case 126: keyboard.send(.move(-1))
        case 36, 76: keyboard.send(.pick)
        default: return false
        }
        return true
    }
}

@MainActor
private final class ChatSwitcherKeyboard: ObservableObject {
    enum Command { case move(Int), pick }
    struct Event {
        let id = UUID()
        let command: Command
    }

    @Published private(set) var event: Event?

    func send(_ command: Command) { event = Event(command: command) }
}

private struct ChatSwitcherView: View {
    @ObservedObject var chat: ChatState
    @ObservedObject var keyboard: ChatSwitcherKeyboard
    let height: CGFloat
    let pick: (ChatSwitcherEntry) -> Void

    @State private var catalog: ChatSwitcherCatalog?
    @State private var loading = true
    @State private var failed = false
    @State private var search = ""
    @State private var highlight: ChatSwitcherEntry.ID?
    @FocusState private var searchFocused: Bool

    init(
        chat: ChatState, keyboard: ChatSwitcherKeyboard, height: CGFloat,
        pick: @escaping (ChatSwitcherEntry) -> Void
    ) {
        self.chat = chat
        self.keyboard = keyboard
        self.height = height
        self.pick = pick
        _catalog = State(initialValue: chat.chatSwitcherCatalog)
    }

    private var groups: [ChatSwitcherGroup] { ChatSwitcherGroup.filter(catalog?.groups ?? [], query: search) }
    private var entries: [ChatSwitcherEntry] { groups.flatMap(\.entries) }
    private var currentID: ChatSwitcherEntry.ID? { chat.reference.map(ChatSwitcherEntry.ID.init) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            threadList.frame(maxHeight: .infinity)
        }
        .padding(4)
        .frame(width: 320, height: height, alignment: .top)
        .background(Theme.overlay)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 1).allowsHitTesting(false) }
        .defaultFocus($searchFocused, true)
        .onAppear { searchFocused = true }
        .task {
            do {
                let refreshed = try await chat.refreshChatSwitcher()
                // Keep the open list stable under the pointer and keyboard highlight.
                // Once there are cached rows, the refresh is shown on the next open.
                if catalog?.groups.isEmpty != false { catalog = refreshed }
            } catch {
                failed = true
            }
            loading = false
        }
        .onChange(of: search) { highlight = entries.first?.id }
        .onChange(of: keyboard.event?.id) {
            if let command = keyboard.event?.command { handle(command) }
        }
    }

    private var searchField: some View {
        PickerSearchField(title: "Search chats", text: $search, focus: $searchFocused)
    }

    private var threadList: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        label(group.id.rawValue)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.entries) { entry in
                            row(entry, group: group.id)
                        }
                    }
                    if groups.isEmpty {
                        if failed { label("Couldn't load chats") }
                        else if loading && catalog == nil { label("Loading chats…") }
                        else { label(search.isEmpty ? "No chats to resume" : "No matching chats") }
                    } else if failed || catalog?.hasUnavailableMachines == true {
                        label(failed ? "Couldn't refresh chats" : "Some machines couldn't load chats")
                    }
                }
                .background(OverlayScrollers())
            }
            .flashScrollKnobsOnHover()
            .onChange(of: highlight) {
                if let highlight { scroll.scrollTo(highlight) }
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
            .frame(height: 21, alignment: .bottom)
    }

    private func row(_ entry: ChatSwitcherEntry, group: ChatSwitcherGroup.Kind) -> some View {
        Button { pick(entry) } label: {
            HStack(spacing: 8) {
                Group {
                    if entry.project == nil && entry.reference.projectName == nil {
                        NoProjectIcon(size: 13)
                    } else {
                        ProjectIconView(
                            project: entry.project, environmentID: entry.id.environmentID,
                            size: 13, fallbackTitle: entry.projectName
                        )
                    }
                }
                .foregroundStyle(Theme.muted)
                .frame(width: 13)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(entry.projectName)
                            .lineLimit(1)
                        if let machine = entry.reference.machineName {
                            Image(systemName: "server.rack")
                                .font(.system(size: 9))
                                .help("On \(machine)")
                                .accessibilityLabel("On \(machine)")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                status(entry, group: group)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(highlight == entry.id ? Theme.highlight : .clear, in: RoundedRectangle(cornerRadius: 8))
            .background(currentID == entry.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .floatButtonStyle(in: RoundedRectangle(cornerRadius: 8))
        .disabled(chat.submitting)
        .id(entry.id)
    }

    private func status(_ entry: ChatSwitcherEntry, group: ChatSwitcherGroup.Kind) -> some View {
        HStack(spacing: 6) {
            if entry.thread.status == .waiting {
                Circle().fill(Theme.warning).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("Needs you")
            } else {
                if group == .working {
                    Canvas { context, _ in
                        for index in 0..<9 {
                            let dot = CGRect(x: (index % 3) * 3, y: (index / 3) * 3, width: 2, height: 2)
                            context.fill(Path(dot), with: .color(Theme.accent.opacity(index.isMultiple(of: 2) ? 1 : 0.35)))
                        }
                    }
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Running")
                } else if group == .pinned {
                    Image(systemName: "pin").font(.system(size: 9)).accessibilityHidden(true)
                }
                if let date = entry.runStartedAt ?? entry.updatedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(age(since: date, at: context.date))
                    }
                }
            }
        }
        .font(.system(size: 10.5).monospacedDigit())
        .foregroundStyle(Theme.muted)
        .fixedSize()
    }

    private func age(since date: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60: return "now"
        case 60..<3_600: return "\(seconds / 60)m"
        case 3_600..<86_400: return "\(seconds / 3_600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    private func handle(_ command: ChatSwitcherKeyboard.Command) {
        let choices = entries
        guard !choices.isEmpty else { return }
        let selected = highlight ?? (search.isEmpty ? currentID : nil)
        let index = choices.firstIndex { $0.id == selected }
        switch command {
        case .move(let direction):
            let next = index.map { ($0 + direction + choices.count) % choices.count }
                ?? (direction > 0 ? 0 : choices.count - 1)
            highlight = choices[next].id
        case .pick:
            if !chat.submitting { pick(choices[index ?? 0]) }
        }
    }
}
