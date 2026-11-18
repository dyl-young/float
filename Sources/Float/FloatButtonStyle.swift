import SwiftUI

enum FloatButtonHighlight {
    case overlay, background, none
}

private struct FloatButtonStyle<Highlight: Shape>: ButtonStyle {
    let shape: Highlight
    let placement: FloatButtonHighlight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(ButtonHighlight(shape: shape, placement: placement))
    }
}

private struct FloatPillButtonStyle: ButtonStyle {
    let tint: Color?
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = enabled ? tint : nil
        let pill = Capsule()
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(fill == nil ? Theme.muted : Theme.canvas)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(fill ?? .clear, in: pill)
            .overlay {
                if fill == nil {
                    pill.strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
            .contentShape(pill)
            .modifier(ButtonHighlight(shape: pill, placement: .overlay))
    }
}

private struct ButtonHighlight<Highlight: Shape>: ViewModifier {
    let shape: Highlight
    let placement: FloatButtonHighlight
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    private var highlight: some View {
        shape.fill(Theme.text.opacity(enabled && (hovered || focused) ? 0.06 : 0))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    func body(content: Content) -> some View {
        content
            .overlay { if placement == .overlay { highlight } }
            .background { if placement == .background { highlight } }
            .onHover { hovered = $0 }
    }
}

extension View {
    func floatPillButtonStyle(tint: Color? = Theme.accent) -> some View {
        buttonStyle(FloatPillButtonStyle(tint: tint))
            .focusEffectDisabled()
    }

    func floatButtonStyle(
        in shape: some Shape = RoundedRectangle(cornerRadius: 6),
        highlight: FloatButtonHighlight = .overlay
    ) -> some View {
        buttonStyle(FloatButtonStyle(shape: shape, placement: highlight))
            .focusEffectDisabled()
    }
}
