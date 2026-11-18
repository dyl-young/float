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
    var isChatSwitcher = false
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, let parent = parent as? FloatPanel {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "k", "n": return parent.performKeyEquivalent(with: event)
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
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
    var openChatSwitcher: (() -> Void)?
    var openModelPicker: (() -> Void)?
    var openProjectPicker: (() -> Void)?
    var openMachinePicker: (() -> Void)?
    var stopRun: (() -> Void)?
    var allowApproval: (() -> Bool)?
    var goBackQuestion: (() -> Bool)?
    var closeQuestionSteps: (() -> Bool)?
    var closeComposerMenu: (() -> Bool)?
    private var captureSharingType: NSWindow.SharingType = .readOnly

    var sizing: PanelSizing?
    /// Set by the app: applies a size a window manager requested through Accessibility.
    var adoptAccessibilitySize: ((NSSize) -> Void)?
    var resizeEnabled = false {
        didSet {
            acceptsMouseMovedEvents = resizeEnabled
            if !resizeEnabled { drag = nil }
            if !resizeEnabled, showingResizeCursor {
                showingResizeCursor = false
                NSCursor.arrow.set()
            }
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
    private var showingResizeCursor = false
    var isResizing: Bool { drag != nil || applyingResize }

    // Window managers skip floating panels and dialogs, and need a settable size.
    // Report a standard window and route Accessibility resizes through Float's limits.
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .standardWindow }

    override func accessibilityIsAttributeSettable(_ attribute: NSAccessibility.Attribute) -> Bool {
        if attribute == .size, adoptAccessibilitySize != nil { return true }
        return super.accessibilityIsAttributeSettable(attribute)
    }

    override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
        if attribute == .size, let adoptAccessibilitySize, let size = (value as? NSValue)?.sizeValue {
            adoptAccessibilitySize(size)
        } else {
            super.accessibilitySetValue(value, forAttribute: attribute)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setScreenSharingHidden(_ hidden: Bool) {
        captureSharingType = hidden ? .none : .readOnly
        sharingType = captureSharingType
        for child in childWindows ?? [] {
            child.sharingType = captureSharingType
        }
    }

    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        childWin.sharingType = captureSharingType
        super.addChildWindow(childWin, ordered: place)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (event.charactersIgnoringModifiers?.lowercased(), modifiers) {
        case ("n", .command):
            if !event.isARepeat {
                childWindows?.compactMap { $0 as? PickerPanel }.first?.dismiss?()
                startNewChat?()
            }
            return true
        case ("k", .command):
            if !event.isARepeat {
                let picker = childWindows?.compactMap { $0 as? PickerPanel }.first
                let wasSwitcher = picker?.isChatSwitcher == true
                picker?.dismiss?()
                if !wasSwitcher { openChatSwitcher?() }
            }
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
        case ("[", .command):
            if !event.isARepeat, (firstResponder as? NSTextView)?.hasMarkedText() != true,
               goBackQuestion?() == true { return true }
            return super.performKeyEquivalent(with: event)
        case ("\r", .command), ("\u{3}", .command):
            if !event.isARepeat, (firstResponder as? NSTextView)?.hasMarkedText() != true,
               allowApproval?() == true { return true }
            if let editor = firstResponder as? PromptTextView, !editor.hasMarkedText() {
                editor.keyDown(with: event)
                return true
            }
            return super.performKeyEquivalent(with: event)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    func closePicker() -> Bool {
        if closeQuestionSteps?() == true { return true }
        if let picker = childWindows?.compactMap({ $0 as? PickerPanel }).first {
            picker.dismiss?()
            return true
        }
        return closeComposerMenu?() == true
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
        if resizeEnabled, updateResizeCursor(for: event) { return }
        super.sendEvent(event)
        if resizeEnabled, event.type == .mouseMoved, let zone = resizeZone(at: event.locationInWindow) {
            // SwiftUI's own tracking areas may have just set a cursor; the edge wins.
            zone.cursor.set()
        }
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

    fileprivate func resizeZone(at point: NSPoint) -> PanelResizeZone? {
        PanelResizeZone.allCases.first { $0.rectangle(in: frame.size).contains(point) }
    }

    /// Cursor rects alone lose to the SwiftUI views under the top edge, so the panel sets the
    /// resize cursor itself: on hover over a grab zone, and for the whole of a drag.
    /// Returns true when it swallowed a cursor update that would have replaced it.
    fileprivate func updateResizeCursor(for event: NSEvent) -> Bool {
        switch event.type {
        case .mouseMoved:
            if resizeZone(at: event.locationInWindow) == nil, showingResizeCursor {
                showingResizeCursor = false
                NSCursor.arrow.set()
            }
            return false
        case .cursorUpdate:
            if let zone = drag?.zone ?? resizeZone(at: event.locationInWindow) {
                zone.cursor.set()
                showingResizeCursor = true
                return true
            }
            return false
        default:
            return false
        }
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
                zone.cursor.set()
                showingResizeCursor = true
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
            drag.zone.cursor.set()
            return true
        case .leftMouseUp:
            guard drag != nil else { return false }
            drag = nil
            sizing.save(frame.size)
            if resizeZone(at: event.locationInWindow) == nil {
                showingResizeCursor = false
                NSCursor.arrow.set()
            }
            invalidateCursorRects(for: contentView ?? NSView())
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
