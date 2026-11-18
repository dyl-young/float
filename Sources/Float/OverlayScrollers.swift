import AppKit
import SwiftUI

final class KnobOnlyScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    static func install(in scroll: NSScrollView) {
        if let vertical = scroll.verticalScroller, !(vertical is KnobOnlyScroller) {
            scroll.verticalScroller = KnobOnlyScroller(frame: vertical.frame)
        }
        if let horizontal = scroll.horizontalScroller, !(horizontal is KnobOnlyScroller) {
            scroll.horizontalScroller = KnobOnlyScroller(frame: horizontal.frame)
        }
        scroll.scrollerStyle = .overlay
    }
}

/// Attach to the content of a SwiftUI scroll view to configure its AppKit scrollers.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.installAfterLayout() }

    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installAfterLayout()
        }

        func installAfterLayout() {
            DispatchQueue.main.async { [weak self] in
                guard let scroll = self?.enclosingScrollView else { return }
                KnobOnlyScroller.install(in: scroll)
            }
        }
    }
}

private struct ScrollKnobHover: ViewModifier {
    @State private var hoverCount = 0

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.visible)
            .scrollIndicatorsFlash(trigger: hoverCount)
            .onHover { if $0 { hoverCount += 1 } }
    }
}

extension View {
    func flashScrollKnobsOnHover() -> some View { modifier(ScrollKnobHover()) }
}
