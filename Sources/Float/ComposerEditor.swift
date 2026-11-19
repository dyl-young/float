import AppKit
import FloatCore
import SwiftUI

/// The composer's text rhythm, matching T3's composer: 14pt text in a `leading-relaxed`
/// line (1.625×), with the extra height split evenly above and below the glyphs as CSS does.
@MainActor
enum ComposerText {
    static let font = NSFont.systemFont(ofSize: 14)
    nonisolated static let lineHeight: CGFloat = 14 * 1.625

    /// TextKit puts a line's extra height above the glyphs; raising them by half of it
    /// centres the text in the line, like CSS half-leading.
    static let baselineOffset: CGFloat = {
        let natural = NSLayoutManager().defaultLineHeight(for: font)
        return max(0, (lineHeight - natural) / 2)
    }()

    static let paragraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }()

    static var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: Theme.textColor,
         .paragraphStyle: paragraph, .baselineOffset: baselineOffset]
    }
}

struct ComposerEditor: NSViewRepresentable {
    @Binding var draft: ComposerDraft
    @Binding var height: CGFloat
    let focusRequest: Int
    let editable: Bool
    let chat: ChatState
    let menu: ComposerMenuState
    let submit: (Bool) -> Void
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
        scroll.scrollerKnobStyle = Theme.isDark(scroll.effectiveAppearance) ? .light : .dark

        let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 24))
        editor.backgroundColor = .clear
        editor.focusRingType = .none
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.textColor = Theme.textColor
        editor.insertionPointColor = Theme.accentColor
        editor.font = ComposerText.font
        editor.defaultParagraphStyle = ComposerText.paragraph
        editor.typingAttributes = ComposerText.attributes
        // The line itself carries T3's spacing, so the container needs no inset.
        editor.textContainerInset = .zero
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
        if !editor.hasMarkedText(), editor.composerDraft != draft {
            // Undo ranges belong to the previous draft when Float replaces
            // the text after a send, chat change, or question change.
            editor.breakUndoCoalescing()
            context.coordinator.editorUndoManager.removeAllActions()
            editor.restore(draft)
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
            parent.draft = editor.composerDraft
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
            parent.menu.close()
            editor.breakUndoCoalescing()
            if case .skill(let skill) = item {
                editor.insertSkill(skill.chip,
                                   replacing: trigger.replacementRange(in: editor.string))
            } else {
                let replacement = item.replacement
                let range = replacement.hasSuffix(" ") ? trigger.replacementRange(in: editor.string) : trigger.range
                editor.insertText(replacement, replacementRange: range)
            }
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
            )
            let measured = min(136, max(ceil(ComposerText.lineHeight), ceil(content)))
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        scrollerKnobStyle = Theme.isDark(effectiveAppearance) ? .light : .dark
    }

    override func mouseEntered(with event: NSEvent) {
        flashScrollers()
    }
}

final class PromptTextView: NSTextView {
    var submit: ((Bool) -> Void)?
    var menuKey: ((NSEvent) -> Bool)?
    var pickOption: ((Int) -> Bool)?
    var pasteImages: ((NSPasteboard) -> Bool)?

    private var plainAttributes: [NSAttributedString.Key: Any] { ComposerText.attributes }

    var composerDraft: ComposerDraft {
        guard let textStorage else { return ComposerDraft(string) }
        var chips: [Int: ComposerSkillChip] = [:]
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) {
            value, range, _ in
            if let attachment = value as? SkillChipAttachment { chips[range.location] = attachment.chip }
        }
        return ComposerDraft(textStorage.string, chips: chips)
    }

    func restore(_ draft: ComposerDraft) {
        let contents = NSMutableAttributedString(string: draft.editorText, attributes: plainAttributes)
        for (location, chip) in draft.chips {
            contents.addAttribute(.attachment, value: SkillChipAttachment(chip: chip),
                                  range: NSRange(location: location, length: 1))
        }
        textStorage?.setAttributedString(contents)
        typingAttributes = plainAttributes
    }

    func insertSkill(_ chip: ComposerSkillChip, replacing range: NSRange) {
        let contents = NSMutableAttributedString(attachment: SkillChipAttachment(chip: chip))
        contents.addAttributes(plainAttributes, range: NSRange(location: 0, length: contents.length))
        contents.append(NSAttributedString(string: " ", attributes: plainAttributes))
        insertText(contents, replacementRange: range)
        typingAttributes = plainAttributes
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        insertionPointColor = Theme.accentColor
        if !hasMarkedText() { typingAttributes = plainAttributes }
        layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0))
        needsDisplay = true
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if isEditable, !hasMarkedText(), selection.length == 0,
           let range = composerDraft.chipDeletionRange(before: selection.location) {
            insertText("", replacementRange: range)
        } else {
            super.deleteBackward(sender)
        }
    }

    override func copy(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(composerDraft.sendText(in: selection), forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard isEditable, selectedRange().length > 0 else { return }
        copy(sender)
        delete(sender)
    }

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
        let shortcut = modifiers.intersection([.command, .shift, .option, .control])
        if [36, 76].contains(event.keyCode), shortcut.isEmpty || shortcut == .command,
            let submit {
            if !event.isARepeat { submit(shortcut == .command) }
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
