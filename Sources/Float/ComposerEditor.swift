import AppKit
import FloatCore
import SwiftUI

struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let focusRequest: Int
    let editable: Bool
    let chat: ChatState
    let menu: ComposerMenuState
    let submit: () -> Void
    let pickOption: (Int) -> Bool
    let pasteImages: (NSPasteboard) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = EditorScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        KnobOnlyScroller.install(in: scroll)
        scroll.scrollerKnobStyle = .light

        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 24))
        editor.backgroundColor = .clear
        editor.focusRingType = .none
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.textColor = NSColor(Theme.text)
        editor.insertionPointColor = NSColor(Theme.accent)
        editor.font = .systemFont(ofSize: 14)
        editor.textContainerInset = NSSize(width: 0, height: 5)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.setAccessibilityLabel("Prompt")
        editor.delegate = context.coordinator
        context.coordinator.editor = editor
        menu.apply = { [weak coordinator = context.coordinator] in coordinator?.apply($0) }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? PromptTextView else { return }
        context.coordinator.parent = self
        editor.submit = submit
        editor.menuKey = { [weak menu, weak chat] event in
            guard let chat else { return false }
            return menu?.handle(event, chat: chat) == true
        }
        editor.pickOption = pickOption
        editor.pasteImages = pasteImages
        editor.isEditable = editable
        if editor.string != text, !editor.hasMarkedText() {
            // Undo ranges belong to the previous draft when Float replaces
            // the text after a send, chat change, or question change.
            editor.breakUndoCoalescing()
            context.coordinator.editorUndoManager.removeAllActions()
            editor.string = text
        }
        let shouldFocus = context.coordinator.focusedRequest != focusRequest
        if shouldFocus { context.coordinator.focusedRequest = focusRequest }
        DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
            guard let editor, let coordinator else { return }
            coordinator.measure(editor)
            if shouldFocus, editor.window?.isVisible == true { editor.window?.makeFirstResponder(editor) }
            coordinator.updateTrigger(editor, edited: false)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        var focusedRequest: Int?
        weak var editor: PromptTextView?
        let editorUndoManager = UndoManager()

        init(_ parent: ComposerEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { editorUndoManager }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? PromptTextView else { return }
            parent.text = editor.string
            updateTrigger(editor, edited: true)
            measure(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? PromptTextView else { return }
            updateTrigger(editor, edited: false)
        }

        func updateTrigger(_ editor: PromptTextView, edited: Bool) {
            let trigger = parent.editable && parent.chat.activeQuestion == nil
                && editor.window?.isVisible == true && !editor.hasMarkedText()
                ? ComposerTrigger.detect(in: editor.string, selection: editor.selectedRange()) : nil
            parent.menu.update(trigger, edited: edited)
        }

        func apply(_ item: ComposerCompletion) {
            guard let editor, editor.isEditable, !editor.hasMarkedText(),
                  let trigger = parent.menu.trigger,
                  trigger == ComposerTrigger.detect(in: editor.string, selection: editor.selectedRange())
            else { return }
            let replacement = item.replacement
            let range = replacement.hasSuffix(" ") ? trigger.replacementRange(in: editor.string) : trigger.range
            guard editor.shouldChangeText(in: range, replacementString: replacement) else { return }
            parent.menu.close()
            editor.breakUndoCoalescing()
            editor.replaceCharacters(in: range, with: replacement)
            editor.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
            editor.didChangeText()
            editor.breakUndoCoalescing()
            if case .builtin(let command) = item { parent.chat.runComposerCommand(command) }
        }

        func measure(_ editor: NSTextView) {
            guard let container = editor.textContainer, let layout = editor.layoutManager else { return }
            if let width = editor.enclosingScrollView?.contentSize.width,
                width > 0, abs(editor.frame.width - width) > 0.5 {
                editor.setFrameSize(NSSize(width: width, height: editor.frame.height))
            }
            layout.ensureLayout(for: container)
            let content = max(
                layout.usedRect(for: container).maxY,
                layout.extraLineFragmentUsedRect.maxY
            ) + 11
            let measured = min(136, max(28, ceil(content)))
            if measured != parent.height { parent.height = measured }
        }
    }
}

private final class EditorScrollView: NSScrollView {
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        flashScrollers()
    }
}

final class PromptTextView: NSTextView {
    var submit: (() -> Void)?
    var menuKey: ((NSEvent) -> Bool)?
    var pickOption: ((Int) -> Bool)?
    var pasteImages: ((NSPasteboard) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let editingModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .function]
        guard !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        if menuKey?(event) == true { return }
        if modifiers.intersection(editingModifiers).isEmpty,
            string.isEmpty, let character = event.charactersIgnoringModifiers,
            let number = Int(character), (1...9).contains(number),
            pickOption?(number - 1) == true {
            return
        }
        if [36, 76].contains(event.keyCode), modifiers.intersection(editingModifiers).isEmpty,
            let submit {
            if !event.isARepeat { submit() }
            return
        }
        super.keyDown(with: event)
    }

    override func deleteToBeginningOfLine(_ sender: Any?) {
        let selection = selectedRange()
        super.deleteToBeginningOfLine(sender)
        // AppKit stops at the start of the line. A subsequent invocation
        // crosses that boundary and deletes back to the preceding line start.
        guard isEditable, !hasMarkedText(), selection.length == 0, selection.location > 0,
              selectedRange() == selection else { return }
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        deleteBackward(sender)
        super.deleteToBeginningOfLine(sender)
    }

    override func cancelOperation(_ sender: Any?) { window?.cancelOperation(sender) }

    override func paste(_ sender: Any?) {
        if pasteImages?(.general) != true { pasteAsPlainText(sender) }
    }
}
