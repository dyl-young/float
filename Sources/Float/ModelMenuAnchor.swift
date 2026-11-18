import AppKit
import Combine
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

@MainActor
private final class ModelPickerPanelController {
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private weak var chat: ChatState?
    private let panel: PickerPanel
    private let keyboard = ModelPickerKeyboard()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var onClose: (() -> Void)?

    init(anchor: NSView, parent: NSWindow, chat: ChatState) {
        self.anchor = anchor
        self.parent = parent
        self.chat = chat
        panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.handleKey = { [weak self] in self?.handleKey($0) == true }
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
        let host = NSHostingView(rootView: ModelPickerView(
            chat: chat, keyboard: keyboard, close: { [weak self] in self?.close() }
        ))
        host.sizingOptions = []
        panel.contentView = host

        let anchorFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        panel.setFrameOrigin(NSPoint(x: anchorFrame.maxX - panel.frame.width, y: anchorFrame.maxY + 6))
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
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            if event.window !== panel {
                close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }
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
private final class ModelPickerKeyboard {
    enum Command {
        case move(Int)
        case pick
    }

    let events = PassthroughSubject<Command, Never>()

    func send(_ command: Command) { events.send(command) }
}

private struct ModelRowTrailingIcons: View {
    let isCurrent: Bool
    let isFavourite: Bool
    let isHovered: Bool
    let tab: T3ModelPickerTabContext
    let toggleFavourite: () -> Void

    private var state: T3ModelRowTrailingState {
        T3ModelRowTrailingState(
            isCurrent: isCurrent, isFavourite: isFavourite,
            isHovered: isHovered, tab: tab
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if state.showsFavouriteToggle {
                Button(action: toggleFavourite) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18, height: 22)
                }
                .floatButtonStyle()
                .help(isFavourite ? "Remove from Favourites" : "Add to Favourites")
            } else if state.showsRestingFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
            }


        }
    }
}

private struct ModelPickerView: View {
    private static let favourites = "favourites"

    @ObservedObject var chat: ChatState
    let keyboard: ModelPickerKeyboard
    let close: () -> Void

    @State private var search = ""
    @State private var selectedTab: String
    @State private var hovered: T3ModelSelection?
    @State private var highlighted: T3ModelKey?
    @State private var searchProviders: [T3ModelProvider]
    @FocusState private var searchFocused: Bool

    init(
        chat: ChatState, keyboard: ModelPickerKeyboard,
        close: @escaping () -> Void
    ) {
        self.chat = chat
        self.keyboard = keyboard
        self.close = close
        _selectedTab = State(
            initialValue: chat.favouriteModelKeys.isEmpty
                ? chat.selectedModel?.instanceId ?? Self.favourites
                : Self.favourites
        )
        _searchProviders = State(initialValue: chat.modelProviders)
    }

    private var providers: [T3ModelProvider] {
        chat.modelProviders.filter(\.appearsInPicker)
    }

    private var selectedProvider: T3ModelProvider? {
        providers.first { $0.instanceId == selectedTab }
    }

    private var displayedModels: [T3Model] {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return searchGroups.flatMap(\.models)
        }
        if selectedTab == Self.favourites {
            return chat.modelProviders.filter(\.enabled).flatMap(\.models).filter {
                chat.favouriteModelKeys.contains(T3ModelKey($0.selection))
            }
        }
        guard let selectedProvider, selectedProvider.enabled else { return [] }
        return selectedProvider.models
    }

    private var searchGroups: [T3ModelSearchGroup] {
        let results = Dictionary(uniqueKeysWithValues: searchProviders.map { ($0.instanceId, $0) })
        let ordered = providers.compactMap { results[$0.instanceId] }
        return T3ModelSearch.groups(providers: ordered, query: search)
    }

    private var turnedOffSearchProviders: [T3ModelProvider] {
        T3ModelSearch.turnedOffProviders(providers: chat.modelProviders, query: search)
    }

    private var rows: [T3ModelKey] {
        displayedModels.map { T3ModelKey($0.selection) }
    }

    private var effortModel: T3Model? {
        guard search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            selectedProvider?.enabled != false,
            let current = chat.selectedCatalogModel
        else { return nil }
        return current
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tabs
            }
            ScrollViewReader { scroll in
                list
                    .frame(maxHeight: .infinity)
                    .onChange(of: highlighted) {
                        if let highlighted { scroll.scrollTo(highlighted) }
                    }
            }
            if let model = effortModel, let option = model.effortOption, !option.stringValues.isEmpty {
                Divider().overlay(Theme.border)
                effortRow(model: model, option: option)
            }
        }
        .padding(4)
        .frame(width: 300, height: 360, alignment: .top)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .defaultFocus($searchFocused, true)
        .onAppear {
            if selectedTab != Self.favourites,
                !providers.contains(where: { $0.instanceId == selectedTab }) {
                selectedTab = providers.first?.instanceId ?? Self.favourites
            }
            searchFocused = true
        }
        .onExitCommand(perform: close)
        .onChange(of: search) {
            highlighted = search.isEmpty ? nil : rows.first
        }
        .onReceive(keyboard.events, perform: handle)
        .task(id: search) {
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                searchProviders = chat.modelProviders
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let results = await chat.searchModelProviders(query)
            guard !Task.isCancelled else { return }
            searchProviders = results
            if highlighted.map(rows.contains) != true { highlighted = rows.first }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("Search models", text: $search)
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

    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(id: Self.favourites, name: "Favourites", systemImage: "star.fill", driverKind: nil, enabled: true)
            ForEach(providers) { provider in
                tabButton(
                    id: provider.instanceId, name: provider.pickerName, systemImage: nil,
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
            .floatButtonStyle()
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
                        .opacity(enabled || selected ? 1 : 0.65)
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
            .contentShape(Rectangle())
        }
        .floatButtonStyle()
        .help(selected ? "" : name)
    }

    @ViewBuilder private var list: some View {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchList
        } else if let provider = selectedProvider, !provider.enabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(provider.pickerName) is turned off in T3.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                Button("Open T3 settings") {
                    chat.openProviderSettings(provider.instanceId)
                    close()
                }
                .floatPillButtonStyle()
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(displayedModels) { model in
                        modelRow(model)
                    }
                    if displayedModels.isEmpty {
                        Text(selectedTab == Self.favourites ? "No favourites yet" : "No models available")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
                .background(OverlayScrollers())
            }
            .flashScrollKnobsOnHover()
            .frame(maxHeight: .infinity)
        }
    }

    private var searchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(searchGroups) { group in
                    Text(group.provider.pickerName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .padding(.top, 5)
                        .frame(height: 24, alignment: .leading)
                    ForEach(group.models) { model in modelRow(model) }
                }
                if searchGroups.isEmpty {
                    Text("No models match \"\(search.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .padding(8)
                }
                if !turnedOffSearchProviders.isEmpty {
                    Text("Turned off in T3: \(turnedOffSearchProviders.map(\.pickerName).joined(separator: ", "))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28, alignment: .leading)
                }
            }
            .background(OverlayScrollers())
        }
        .flashScrollKnobsOnHover()
        .frame(maxHeight: .infinity)
    }

    private func modelRow(_ model: T3Model) -> some View {
        let row = T3ModelKey(model.selection)
        let isCurrent = model.selection.matches(chat.selectedModel)
        let isFavourite = chat.isFavourite(model)
        return HStack(spacing: 8) {
            ProviderGlyph(driverKind: model.driverKind)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.shortLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if selectedTab == Self.favourites && search.isEmpty {
                    Text(model.provider)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                row == highlighted {
                keyCap("↵")
            }
            ModelRowTrailingIcons(
                isCurrent: isCurrent,
                isFavourite: isFavourite,
                isHovered: hovered == model.selection,
                tab: search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (selectedTab == Self.favourites ? .favourites : .provider)
                    : .search,
                toggleFavourite: { chat.toggleFavourite(model) }
            )
        }
        .padding(.horizontal, 8)
        .frame(minHeight: selectedTab == Self.favourites && search.isEmpty ? 36 : 28)
        .background(
            highlighted == row || hovered == model.selection ? Theme.text.opacity(0.06) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .background(isCurrent ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .id(row)
        .onHover {
            hovered = $0 ? model.selection : nil
        }
        .onTapGesture {
            chat.selectModel(model)
            close()
        }
    }

    private func effortRow(model: T3Model, option: T3ModelOption) -> some View {
        let selected = chat.effort(for: model)
        return HStack(spacing: 6) {
            Text("Effort")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(option.stringValues, id: \.self) { value in
                    Button {
                        chat.setEffort(value, for: model)
                    } label: {
                        Text(effortLabel(value))
                            .font(.system(size: 10.5))
                            .foregroundStyle(selected == value ? Theme.text : Theme.muted)
                            .padding(.horizontal, 4)
                            .frame(height: 20)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(selected == value ? Theme.text.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .floatButtonStyle()
                    .help(effortName(value))
                    .accessibilityLabel(effortName(value))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(2)
            .background(Theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
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
        case "ultrathink": "Ultra"
        default: effortName(value)
        }
    }

    private func effortName(_ value: String) -> String {
        value.lowercased() == "xhigh" ? "Extra High" : value.capitalized
    }

    private func handle(_ command: ModelPickerKeyboard.Command) {
        switch command {
        case .move(let direction):
            hovered = nil
            let rows = rows
            let current = highlighted.flatMap { rows.firstIndex(of: $0) }
            if let index = T3ModelPickerNavigation.move(from: current, by: direction, count: rows.count) {
                highlighted = rows[index]
            }
        case .pick:
            guard let key = highlighted ?? rows.first,
                let model = displayedModels.first(where: { T3ModelKey($0.selection) == key })
            else { return }
            chat.selectModel(model)
            close()
        }
    }
}
