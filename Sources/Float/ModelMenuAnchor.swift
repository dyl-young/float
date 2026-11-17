import AppKit
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

        init(request: Int) {
            self.request = request
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func showMenu(for chat: ChatState) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(.sectionHeader(title: "Select model"))

            if chat.loadingModels {
                menu.addItem(MenuAction("Loading models…", action: nil))
            } else if chat.modelCatalogFailed {
                menu.addItem(MenuAction("Couldn’t load models from T3", action: nil))
            } else if chat.models.isEmpty {
                menu.addItem(MenuAction("No enabled Codex or Claude models", action: nil))
            }

            if chat.defaultModel != nil {
                menu.addItem(MenuAction("Default", selected: chat.usesDefaultModel) {
                    chat.selectModel(nil)
                })
            }
            for model in chat.models {
                let duplicate = chat.models.contains { $0.id != model.id && $0.label == model.label }
                let title = duplicate ? "\(model.label) · \(model.provider)" : model.label
                menu.addItem(MenuAction(title, selected: !chat.usesDefaultModel && model.selection == chat.selectedModel) {
                    chat.selectModel(model)
                })
            }

            menu.addItem(.separator())
            let reload = MenuAction("Reload Models") { chat.reloadModels() }
            reload.isEnabled = !chat.loadingModels
            menu.addItem(reload)
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.minY), in: self)
        }
    }
}

private final class MenuAction: NSMenuItem {
    private let handler: (() -> Void)?

    init(_ title: String, selected: Bool = false, action: (() -> Void)?) {
        handler = action
        super.init(title: title, action: action == nil ? nil : #selector(invoke), keyEquivalent: "")
        target = self
        isEnabled = action != nil
        state = selected ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Menu items are created in code.") }

    @objc private func invoke() { handler?() }
}
