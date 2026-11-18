import AppKit
import FloatCore
import SwiftUI

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
final class PickerPanel: EditingPanel {
    override var canBecomeKey: Bool { true }
    var dismiss: (() -> Void)?
    var handleKey: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true {
            if event.isPlainEscape {
                if !event.isARepeat { dismiss?() }
                return
            }
            if handleKey?(event) == true { return }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { dismiss?() }
}

private extension NSEvent {
    var isPlainEscape: Bool {
        keyCode == 53 && modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
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
    var allowApproval: (() -> Bool)?

    var sizing: PanelSizing?
    var resizeEnabled = false {
        didSet {
            if !resizeEnabled { drag = nil }
            if let contentView { invalidateCursorRects(for: contentView) }
        }
    }

    private struct Drag {
        let zone: PanelResizeZone
        let frame: NSRect
        let pointer: NSPoint
    }

    private var drag: Drag?
    private var applyingResize = false
    var isResizing: Bool { drag != nil || applyingResize }

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
        case ("h", [.command, .shift]):
            if !event.isARepeat { openMachinePicker?() }
            return true
        case (".", .command):
            if !event.isARepeat { stopRun?() }
            return true
        case ("\r", .command), ("\u{3}", .command):
            if !event.isARepeat, (firstResponder as? NSTextView)?.hasMarkedText() != true,
               allowApproval?() == true { return true }
            return super.performKeyEquivalent(with: event)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    func closePicker() -> Bool {
        guard let picker = childWindows?.compactMap({ $0 as? PickerPanel }).first else { return false }
        picker.dismiss?()
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        if !closePicker() { dismiss?() }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.isPlainEscape,
           (firstResponder as? NSTextView)?.hasMarkedText() != true {
            if !event.isARepeat { cancelOperation(nil) }
            return
        }
        if resizeEnabled, let sizing, handleResize(event, sizing: sizing) { return }
        super.sendEvent(event)
    }
}

extension FloatPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // During a resize AppKit may reposition the window to keep it onscreen.
        // The drag owns its bottom edge and the side opposite the pointer.
        applyingResize ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    private func applyResize(_ frame: NSRect) {
        applyingResize = true
        defer { applyingResize = false }
        setFrame(frame, display: true)
    }

    private func handleResize(_ event: NSEvent, sizing: PanelSizing) -> Bool {
        let visibleHeight = screen?.visibleFrame.height ?? 1_000
        switch event.type {
        case .leftMouseDown:
            let size = frame.size
            let point = event.locationInWindow
            guard let zone = PanelResizeZone.allCases.first(where: {
                $0.rectangle(in: size).contains(point)
            }) else { return false }
            if event.clickCount == 2, zone == .top {
                sizing.reset()
                var resetFrame = frame
                resetFrame.size = CGSize(width: sizing.width, height: sizing.height(on: visibleHeight))
                applyResize(resetFrame)
            } else {
                drag = Drag(zone: zone, frame: frame, pointer: convertPoint(toScreen: point))
            }
            return true
        case .leftMouseDragged:
            guard let drag else { return false }
            let pointer = convertPoint(toScreen: event.locationInWindow)
            let dx = pointer.x - drag.pointer.x
            let dy = pointer.y - drag.pointer.y
            var next = drag.frame
            next.size.height = sizing.clampHeight(Double(drag.frame.height + dy), on: visibleHeight)
            switch drag.zone {
            case .top: break
            case .topLeft:
                next.size.width = CGFloat(PanelWidthLimits.clamp(Double(drag.frame.width - dx)))
                next.origin.x = drag.frame.maxX - next.width
            case .topRight:
                next.size.width = CGFloat(PanelWidthLimits.clamp(Double(drag.frame.width + dx)))
            }
            applyResize(next)
            return true
        case .leftMouseUp:
            guard drag != nil else { return false }
            drag = nil
            sizing.save(frame.size)
            return true
        default:
            return false
        }
    }
}

private enum PanelResizeZone: CaseIterable {
    case topLeft, topRight, top

    func rectangle(in size: CGSize, flipped: Bool = false) -> CGRect {
        switch self {
        case .topLeft: CGRect(x: 0, y: flipped ? 0 : size.height - 10, width: 10, height: 10)
        case .topRight: CGRect(x: size.width - 10, y: flipped ? 0 : size.height - 10, width: 10, height: 10)
        case .top: CGRect(x: 10, y: flipped ? 0 : size.height - 4, width: size.width - 20, height: 4)
        }
    }

    @MainActor var cursor: NSCursor {
        switch self {
        case .top: return .resizeUpDown
        case .topLeft, .topRight:
            if #available(macOS 15.0, *) {
                return .frameResize(position: self == .topLeft ? .topLeft : .topRight, directions: .all)
            }
            if let image = NSImage(
                systemSymbolName: self == .topLeft ? "arrow.up.left.and.arrow.down.right" : "arrow.up.right.and.arrow.down.left",
                accessibilityDescription: "Resize"
            ) {
                return NSCursor(image: image, hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2))
            }
            return .resizeUpDown
        }
    }
}

final class FloatPanelHostingView: NSHostingView<FloatView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        guard (window as? FloatPanel)?.resizeEnabled == true else { return }
        for zone in PanelResizeZone.allCases {
            addCursorRect(zone.rectangle(in: bounds.size, flipped: isFlipped), cursor: zone.cursor)
        }
    }
}
