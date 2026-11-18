import AppKit
import FloatCore
import SwiftUI

@MainActor
final class ComposerMenuState: ObservableObject {
    struct InventoryTarget: Equatable {
        let instanceID: String
        let cwd: String?
    }

    struct Section: Identifiable {
        let id: ComposerCompletion.Group
        var items: [ComposerCompletion]
    }

    @Published private(set) var trigger: ComposerTrigger?
    @Published private(set) var highlightedID: String?
    @Published private var inventory: T3ComposerInventory = .empty
    @Published private(set) var loadedTarget: InventoryTarget?
    @Published private(set) var loadFailed = false

    private var dismissedTrigger: ComposerTrigger?
    private var loadedAt = Date.distantPast
    var apply: ((ComposerCompletion) -> Void)?

    func update(_ next: ComposerTrigger?, edited: Bool) {
        if edited || next != dismissedTrigger { dismissedTrigger = nil }
        let active = dismissedTrigger == nil ? next : nil
        guard trigger != active else { return }
        trigger = active
        highlightedID = nil
    }

    @discardableResult func close() -> Bool {
        guard let trigger else { return false }
        dismissedTrigger = trigger
        self.trigger = nil
        highlightedID = nil
        return true
    }

    func load(_ target: InventoryTarget, chat: ChatState) async {
        if loadedTarget == target, Date.now.timeIntervalSince(loadedAt) < 300 { return }
        do {
            let result = try await chat.loadComposerInventory(target)
            guard !Task.isCancelled else { return }
            inventory = result
            loadedAt = .now
            loadFailed = false
            loadedTarget = target
        } catch {
            guard !Task.isCancelled else { return }
            inventory = .empty
            loadedAt = .distantPast
            loadFailed = true
            loadedTarget = target
        }
    }

    func hasSkills(for chat: ChatState) -> Bool {
        loadedTarget == chat.composerInventoryTarget && inventory.skills.contains {
            $0.enabled && $0.userInvocable != false
        }
    }

    func sections(for chat: ChatState) -> [Section] {
        guard let trigger else { return [] }
        let items = ComposerCompletion.matches(
            trigger, inventory: loadedTarget == chat.composerInventoryTarget ? inventory : .empty,
            canClear: !chat.submitting
        )
        var sections: [Section] = []
        for item in items {
            if let index = sections.firstIndex(where: { $0.id == item.group }) {
                sections[index].items.append(item)
            } else {
                sections.append(Section(id: item.group, items: [item]))
            }
        }
        return sections
    }

    func selection(in items: [ComposerCompletion]) -> ComposerCompletion? {
        items.first { $0.id == highlightedID } ?? items.first
    }

    func handle(_ event: NSEvent, chat: ChatState) -> Bool {
        guard trigger != nil,
              event.modifierFlags.intersection([.command, .shift, .option, .control, .function]).isEmpty else {
            return false
        }
        let items = sections(for: chat).flatMap(\.items)
        guard let selected = selection(in: items) else { return false }
        switch event.keyCode {
        case 125, 126:
            if let index = items.firstIndex(of: selected) {
                let offset = event.keyCode == 125 ? 1 : -1
                highlightedID = items[(index + offset + items.count) % items.count].id
            }
        case 36, 76, 48:
            if !event.isARepeat { apply?(selected) }
        default:
            return false
        }
        return true
    }
}

struct ComposerMenuAnchor: NSViewRepresentable {
    let chat: ChatState
    @ObservedObject var menu: ComposerMenuState

    func makeNSView(context: Context) -> Anchor { Anchor() }

    func updateNSView(_ anchor: Anchor, context: Context) {
        guard let trigger = menu.trigger else {
            anchor.close()
            return
        }
        let sections = menu.sections(for: chat)
        let selected = menu.selection(in: sections.flatMap(\.items))
        let view = ComposerMenuView(
            sections: sections, selected: selected?.id, kind: trigger.kind,
            providerName: chat.composerProviderName, driverKind: chat.composerDriverKind,
            emptyLabel: emptyLabel(trigger), pick: { [weak menu] in menu?.apply?($0) }
        )
        anchor.present(view, menu: menu)
    }

    static func dismantleNSView(_ anchor: Anchor, coordinator: ()) { anchor.close() }

    private func emptyLabel(_ trigger: ComposerTrigger) -> String {
        if let target = chat.composerInventoryTarget {
            if menu.loadedTarget != target { return "Loading \(chat.composerProviderName) suggestions…" }
            if menu.loadFailed { return "Suggestions unavailable" }
        }
        if trigger.kind == .skill && (!menu.hasSkills(for: chat) || trigger.query.isEmpty) {
            return "No skills for \(chat.composerProviderName)"
        }
        return trigger.kind == .skill ? "No matching skills" : "No matching commands"
    }

    final class Anchor: NSView {
        private var panel: SuggestionPanel?
        private var host: MenuHostingView?
        private var height: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            positionPanel()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            positionPanel()
        }

        fileprivate func present(_ view: ComposerMenuView, menu: ComposerMenuState) {
            (window as? FloatPanel)?.closeComposerMenu = { [weak menu] in menu?.close() == true }
            height = view.height
            if let host {
                host.rootView = view
            } else {
                let popup = SuggestionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
                popup.isOpaque = false
                popup.backgroundColor = .clear
                popup.hasShadow = true
                popup.hidesOnDeactivate = false
                popup.becomesKeyOnlyIfNeeded = true
                popup.isMovableByWindowBackground = false
                popup.collectionBehavior = [.transient, .fullScreenAuxiliary]
                let hosting = MenuHostingView(rootView: view)
                hosting.sizingOptions = []
                popup.contentView = hosting
                panel = popup
                host = hosting
            }
            DispatchQueue.main.async { [weak self] in self?.positionPanel() }
        }

        func close() {
            guard let panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
            host = nil
        }

        private func positionPanel() {
            guard let window, let panel, window.isVisible, bounds.width > 0 else { return }
            let anchor = window.convertToScreen(convert(bounds, to: nil))
            let bottom = anchor.maxY + 10
            let space = window.screen.map { $0.visibleFrame.maxY - bottom } ?? height
            let shownHeight = min(height, max(0, space))
            guard shownHeight >= 36 else {
                panel.orderOut(nil)
                return
            }
            let frame = NSRect(x: anchor.minX + 11, y: bottom, width: max(1, anchor.width - 22),
                               height: shownHeight)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private final class MenuHostingView: NSHostingView<ComposerMenuView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private final class SuggestionPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}

private struct ComposerMenuView: View {
    let sections: [ComposerMenuState.Section]
    let selected: String?
    let kind: ComposerTrigger.Kind
    let providerName: String
    let driverKind: String?
    let emptyLabel: String
    let pick: (ComposerCompletion) -> Void

    var height: CGFloat {
        let rows = max(1, sections.reduce(0) { $0 + $1.items.count })
        let headers = kind == .slash ? sections.count : 0
        return min(288, CGFloat(rows * 28 + headers * 22 + 8))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if sections.isEmpty {
                            Text(emptyLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                        }
                        ForEach(sections) { section in
                            if kind == .slash {
                                Text(title(for: section.id))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 8)
                                    .padding(.top, 3)
                                    .frame(height: 22)
                            }
                            ForEach(section.items) { item in
                                row(item, nameWidth: (geometry.size.width - 8) * 0.45)
                                    .id(item.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(OverlayScrollers())
                }
                .flashScrollKnobsOnHover()
                .onChange(of: selected) {
                    if let selected { proxy.scrollTo(selected) }
                }
            }
        }
        .background(Theme.raised, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Theme.border).allowsHitTesting(false) }
        .preferredColorScheme(.dark)
    }

    private func row(_ item: ComposerCompletion, nameWidth: CGFloat) -> some View {
        let isSelected = item.id == selected
        let shape = RoundedRectangle(cornerRadius: 8)
        let label: String
        if case .skill(let skill) = item {
            label = kind == .skill ? skill.label : "/skill:" + skill.name
        } else {
            label = "/" + item.name
        }
        let naturalWidth = ceil((label as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        ).width)
        return Button { pick(item) } label: {
            HStack(spacing: 8) {
                Image(systemName: item.group == .skills ? "bolt" : "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 13, height: 13)
                name(for: item)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(width: min(naturalWidth, nameWidth), alignment: .leading)
                    .layoutPriority(1)
                Text(item.description)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Text("↵")
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                }
                if item.group != .commands {
                    ProviderGlyph(driverKind: driverKind)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background { if isSelected { shape.fill(Theme.selection) } }
            .contentShape(shape)
        }
        .floatButtonStyle(in: shape, highlight: isSelected ? .none : .background)
    }

    private func name(for item: ComposerCompletion) -> Text {
        if case .skill(let skill) = item {
            if kind == .skill { return Text(skill.label) }
            return Text("\(Text("/skill:").fontWeight(.regular).foregroundColor(Theme.muted))\(skill.name)")
        }
        return Text("/" + item.name)
    }

    private func title(for group: ComposerCompletion.Group) -> String {
        switch group {
        case .commands: "Commands"
        case .provider: providerName
        case .skills: "Skills"
        }
    }
}
