import AppKit

@MainActor
class EditingPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let editor = firstResponder as? NSTextView else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (event.charactersIgnoringModifiers?.lowercased(), modifiers) {
        case ("a", .command): editor.selectAll(nil)
        case ("c", .command): editor.copy(nil)
        case ("x", .command): editor.cut(nil)
        case ("v", .command): editor.paste(nil)
        case ("z", .command): editor.undoManager?.undo()
        case ("z", [.command, .shift]): editor.undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

@MainActor
final class FloatPanel: EditingPanel {
    var dismiss: (() -> Void)?
    var startNewChat: (() -> Void)?
    var openModelPicker: (() -> Void)?
    var openProjectPicker: (() -> Void)?
    var openMachinePicker: (() -> Void)?
    var stopRun: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (event.charactersIgnoringModifiers?.lowercased(), modifiers) {
        case ("n", .command):
            if !event.isARepeat { startNewChat?() }
            return true
        case ("m", [.command, .shift]):
            if !event.isARepeat { openModelPicker?() }
            return true
        case ("p", [.command, .shift]):
            if !event.isARepeat { openProjectPicker?() }
            return true
        case ("h", .command):
            if !event.isARepeat { openMachinePicker?() }
            return true
        case (".", .command):
            if !event.isARepeat { stopRun?() }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { dismiss?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            dismiss?()
        } else {
            super.keyDown(with: event)
        }
    }
}
