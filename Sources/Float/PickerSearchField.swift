import SwiftUI

struct PickerSearchField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField(title, text: $text, prompt: colorScheme == .light ? Text(verbatim: "") : nil)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(Theme.text)
                .focused(focus)
                .overlay(alignment: .leading) {
                    if colorScheme == .light, text.isEmpty {
                        Text(title)
                            .foregroundStyle(Theme.searchPlaceholder)
                            .padding(.leading, 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .font(.system(size: 11.5))
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .padding(2)
        .padding(.bottom, 2)
    }
}
