import AppKit
import SwiftUI

struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let focusRequest: Int
    let submit: () -> Void
    let pasteImages: (NSPasteboard) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 24))
        editor.backgroundColor = .clear
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.textColor = NSColor(FloatPalette.text)
        editor.insertionPointColor = NSColor(FloatPalette.accent)
        editor.font = .systemFont(ofSize: 14)
        editor.textContainerInset = NSSize(width: 0, height: 5)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.setAccessibilityLabel("Prompt")
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? PromptTextView else { return }
        context.coordinator.parent = self
        editor.submit = submit
        editor.pasteImages = pasteImages
        if editor.string != text, !editor.hasMarkedText() { editor.string = text }
        let shouldFocus = context.coordinator.focusedRequest != focusRequest
        if shouldFocus { context.coordinator.focusedRequest = focusRequest }
        DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
            guard let editor, let coordinator else { return }
            coordinator.measure(editor)
            if shouldFocus, editor.window?.isVisible == true { editor.window?.makeFirstResponder(editor) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        var focusedRequest: Int?

        init(_ parent: ComposerEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            measure(editor)
        }

        @MainActor func measure(_ editor: NSTextView) {
            guard let container = editor.textContainer, let layout = editor.layoutManager else { return }
            layout.ensureLayout(for: container)
            let content = layout.usedRect(for: container).height + 11
            let measured = min(136, max(28, ceil(content)))
            if measured != parent.height { parent.height = measured }
        }
    }
}

final class PromptTextView: NSTextView {
    var submit: (() -> Void)?
    var pasteImages: ((NSPasteboard) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if [36, 76].contains(event.keyCode), modifiers.intersection([.shift, .option, .control]).isEmpty,
            !hasMarkedText() {
            submit?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { window?.cancelOperation(sender) }

    override func paste(_ sender: Any?) {
        if pasteImages?(.general) != true { pasteAsPlainText(sender) }
    }
}
