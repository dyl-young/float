import SwiftUI

struct ApprovalCard: View {
    let preview: String
    let optIn: (() -> Void)?
    let busy: Bool
    let error: String?
    let openInT3: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Needs your approval")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if optIn != nil {
                    Text("This gives Float a T3 key that can also start runs. You can turn it off from the menu bar.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.error)
                }
                HStack(spacing: 9) {
                    if let optIn {
                        primaryButton("Answer approvals in Float", action: optIn)
                            .disabled(busy)
                    }
                    if let openInT3 {
                        Button(action: openInT3) {
                            Text("Open in T3")
                                .font(.system(size: 11))
                                .underline()
                                .foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.warning.opacity(0.45), lineWidth: 1) }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.canvas)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
