import AppKit

@MainActor
final class FloatPanel: NSPanel {
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
        case ("r", [.command, .shift]):
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
