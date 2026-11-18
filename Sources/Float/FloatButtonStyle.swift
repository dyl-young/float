import SwiftUI

private struct FloatButtonStyle<Highlight: Shape>: ButtonStyle {
    let highlight: Highlight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(ButtonHighlight(shape: highlight))
    }
}

private struct ButtonHighlight<Highlight: Shape>: ViewModifier {
    let shape: Highlight
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                shape.fill(Theme.text.opacity(enabled && (hovered || focused) ? 0.06 : 0))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onHover { hovered = $0 }
    }
}

extension View {
    func floatButtonStyle(in highlight: some Shape = RoundedRectangle(cornerRadius: 6)) -> some View {
        buttonStyle(FloatButtonStyle(highlight: highlight))
            .focusEffectDisabled()
    }
}
