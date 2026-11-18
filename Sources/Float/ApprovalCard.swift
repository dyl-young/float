import FloatCore
import SwiftUI

struct ApprovalCard: View {
    let request: ApprovalRequest?
    let count: Int
    let preview: String?
    let optIn: (() -> Void)?
    let busy: Bool
    let error: String?
    let openInT3: (() -> Void)?
    let respond: (ApprovalDecision, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Needs your approval")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if count > 1 {
                        Spacer(minLength: 8)
                        Text("1 of \(count)")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                }
                if let request {
                    requestDetails(request)
                } else if let preview {
                    detail(preview)
                }
                if optIn != nil {
                    detail("This gives Float a T3 key that can also start runs. You can turn it off from the menu bar.",
                           muted: true)
                }
                if let error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(Theme.warningSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.warning.opacity(0.45), lineWidth: 1) }
    }

    @ViewBuilder private func requestDetails(_ request: ApprovalRequest) -> some View {
        let paths = request.paths.isEmpty ? nil : request.paths.joined(separator: ", ")
        Text(requestText(request))
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        if let text = request.detail { detail(text) }
        if let paths {
            Text(inlineCode(paths))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        if let reason = request.reason { detail(reason, muted: true) }
    }

    private func requestText(_ request: ApprovalRequest) -> AttributedString {
        var text = AttributedString(request.action)
        if let command = request.command {
            text += AttributedString(" ")
            text += inlineCode(command)
        }
        return text
    }

    private func inlineCode(_ text: String) -> AttributedString {
        var code = AttributedString(text)
        code.font = .system(size: 11.5, design: .monospaced)
        code.backgroundColor = Theme.text.opacity(0.10)
        return code
    }

    private func detail(_ text: String, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: muted ? 11 : 12))
            .foregroundStyle(muted ? Theme.muted : Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 7) {
            if let optIn {
                pill("Answer approvals in Float", action: optIn)
                    .disabled(busy)
            }
            if let request, request.allowedDecisions.contains(.allow) {
                pill("Allow", action: { respond(.allow, request.id) })
                    .help("Allow once (⌘↵)")
                    .disabled(busy)
            }
            if let request, request.allowedDecisions.contains(.deny) {
                pill("Deny", primary: false, action: { respond(.deny, request.id) })
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

    private func pill(_ title: String, primary: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(primary ? Theme.canvas : Theme.muted)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(primary ? Theme.accent : Color.clear, in: Capsule())
                .overlay {
                    if !primary { Capsule().strokeBorder(Theme.border, lineWidth: 1) }
                }
                .opacity(busy ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }
}
