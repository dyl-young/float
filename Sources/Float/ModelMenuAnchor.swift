import AppKit
import FloatCore
import SwiftUI

struct ModelMenuAnchor: NSViewRepresentable {
    let chat: ChatState
    let request: Int

    func makeNSView(context: Context) -> Anchor { Anchor(request: request) }

    func updateNSView(_ anchor: Anchor, context: Context) {
        guard anchor.request != request else { return }
        anchor.request = request

        DispatchQueue.main.async { [weak anchor, weak chat] in
            guard let anchor, let chat, anchor.request == request, chat.canChooseModel,
                anchor.window?.isKeyWindow == true
            else { return }
            anchor.showMenu(for: chat)
        }
    }

    final class Anchor: NSView {
        var request: Int
        private var picker: ModelPickerPanelController?

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
            let controller = ModelPickerPanelController(anchor: self, parent: window, chat: chat)
            picker = controller
            controller.show { [weak self] in self?.picker = nil }
        }
    }
}

private final class ModelPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class ModelPickerPanelController {
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private weak var chat: ChatState?
    private let panel: ModelPickerPanel
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onClose: (() -> Void)?

    init(anchor: NSView, parent: NSWindow, chat: ChatState) {
        self.anchor = anchor
        self.parent = parent
        self.chat = chat
        panel = ModelPickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    }

    func show(onClose: @escaping () -> Void) {
        guard let anchor, let parent else { return }
        self.onClose = onClose
        let content = ModelPickerView(chat: chat!, close: { [weak self] in self?.close() })
        panel.contentView = NSHostingView(rootView: content)

        let anchorFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: anchorFrame.maxX - panel.frame.width, y: anchorFrame.maxY + 6)
        origin.x = min(max(visible.minX + 6, origin.x), visible.maxX - panel.frame.width - 6)
        if origin.y + panel.frame.height > visible.maxY {
            origin.y = anchorFrame.minY - panel.frame.height - 6
        }
        panel.setFrameOrigin(origin)
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

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
            [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                close()
                return nil
            }
            if event.type != .keyDown, event.window !== panel {
                close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

}

private struct ModelPickerView: View {
    private static let favourites = "favourites"

    @ObservedObject var chat: ChatState
    let close: () -> Void

    @State private var search = ""
    @State private var selectedTab: String
    @State private var favourites: Set<T3ModelSelection> = []
    @State private var hovered: T3ModelSelection?
    @State private var highlighted: T3ModelSelection?
    @State private var efforts: [T3ModelSelection: String] = [:]
    @FocusState private var searchFocused: Bool

    init(chat: ChatState, close: @escaping () -> Void) {
        self.chat = chat
        self.close = close
        _selectedTab = State(initialValue: chat.selectedModel?.instanceId ?? Self.favourites)
    }

    private var providers: [T3ModelProvider] {
        chat.modelProviders.filter { ProviderIcon(driverKind: $0.driverKind) != nil }
    }

    private var selectedProvider: T3ModelProvider? {
        providers.first { $0.instanceId == selectedTab }
    }

    private var displayedModels: [T3Model] {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return chat.modelProviders.flatMap(\.models).filter { matches($0, query: search) }
        }
        if selectedTab == Self.favourites {
            return chat.modelProviders.flatMap(\.models).filter { favourites.contains($0.selection) }
        }
        return selectedProvider?.models ?? []
    }

    private var effortModel: T3Model? {
        let target = highlighted ?? chat.selectedModel
        return chat.modelProviders.flatMap(\.models).first { $0.selection.matches(target) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tabs
            }
            list
            if let model = effortModel, let option = model.effortOption, !option.stringValues.isEmpty {
                Divider().overlay(Theme.border)
                effortRow(model: model, option: option)
            }
            hintRow
        }
        .padding(4)
        .frame(width: 290, height: 300, alignment: .top)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !providers.contains(where: { $0.instanceId == selectedTab }) {
                selectedTab = providers.first?.instanceId ?? Self.favourites
            }
            searchFocused = true
        }
        .onExitCommand(perform: close)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("Search models", text: $search)
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

    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(id: Self.favourites, name: "Favourites", systemImage: "star.fill", driverKind: nil, enabled: true)
            ForEach(providers) { provider in
                tabButton(
                    id: provider.instanceId, name: provider.displayName, systemImage: nil,
                    driverKind: provider.driverKind, enabled: provider.enabled
                )
            }
            Spacer(minLength: 0)
            Button(action: chat.reloadModels) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(chat.loadingModels)
            .help("Reload models")
        }
        .frame(height: 28)
        .padding(.horizontal, 2)
    }

    private func tabButton(
        id: String, name: String, systemImage: String?, driverKind: String?, enabled: Bool
    ) -> some View {
        let selected = selectedTab == id
        return Button {
            selectedTab = id
            highlighted = nil
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10.5, weight: .medium))
                } else {
                    ProviderGlyph(driverKind: driverKind)
                }
                if selected {
                    Text(name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.muted)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(selected ? Theme.text.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(enabled || selected ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(selected ? "" : name)
    }

    @ViewBuilder private var list: some View {
        if let provider = selectedProvider, !provider.enabled, search.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(provider.displayName) is turned off in T3.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                Button("Open T3 settings") {
                    chat.openProviderSettings(provider.instanceId)
                    close()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.canvas)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Theme.accent, in: Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    if selectedTab == Self.favourites, search.isEmpty {
                        defaultRow
                    }
                    ForEach(displayedModels) { model in
                        modelRow(model)
                    }
                    if displayedModels.isEmpty {
                        Text(search.isEmpty ? "No favourites yet" : "No match")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)
        }
    }

    private var defaultRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 13)
            Text("Use T3 default")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
            Spacer()
            if chat.usesDefaultModel {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(chat.usesDefaultModel ? Theme.text.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            chat.selectModel(nil)
            close()
        }
    }

    private func modelRow(_ model: T3Model) -> some View {
        let isCurrent = !chat.usesDefaultModel && model.selection.matches(chat.selectedModel)
        let isFavourite = favourites.contains(model.selection)
        return HStack(spacing: 8) {
            ProviderGlyph(driverKind: model.driverKind)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.shortLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if selectedTab == Self.favourites || !search.isEmpty {
                    Text(model.provider)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if hovered == model.selection || isFavourite {
                Button {
                    if isFavourite {
                        favourites.remove(model.selection)
                    } else {
                        favourites.insert(model.selection)
                    }
                } label: {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isFavourite ? Theme.accent : Theme.muted)
                        .frame(width: 18, height: 22)
                }
                .buttonStyle(.plain)
                .help(isFavourite ? "Remove from Favourites" : "Add to Favourites")
            } else if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: selectedTab == Self.favourites || !search.isEmpty ? 36 : 28)
        .background(isCurrent || highlighted == model.selection ? Theme.text.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover {
            hovered = $0 ? model.selection : nil
            if $0 { highlighted = model.selection }
        }
        .onTapGesture {
            chat.selectModel(model)
            close()
        }
    }

    private func effortRow(model: T3Model, option: T3ModelOption) -> some View {
        let selected = efforts[model.selection] ?? option.defaultString ?? option.stringValues.first
        return HStack(spacing: 6) {
            Text("Effort")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 2) {
                ForEach(option.stringValues, id: \.self) { value in
                    Button {
                        efforts[model.selection] = value
                    } label: {
                        Text(effortLabel(value))
                            .font(.system(size: 10.5))
                            .foregroundStyle(selected == value ? Theme.text : Theme.muted)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(selected == value ? Theme.text.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }

    private var hintRow: some View {
        HStack(spacing: 6) {
            keyCap("⌘1–\(min(9, providers.count + 1))")
            Text("switch tab")
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

    private func effortLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "medium": "Med"
        case "xhigh": "XHigh"
        default: value.capitalized
        }
    }

    private func matches(_ model: T3Model, query: String) -> Bool {
        let normalizedQuery = normalize(query)
        return normalize([model.label, model.selection.model, model.provider].joined(separator: " "))
            .contains(normalizedQuery)
    }

    private func normalize(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
