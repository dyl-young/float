import AppKit
import FloatCore
import SwiftUI
import UniformTypeIdentifiers

/// One shell, three layers: a solid message tray on top, the frosted input in the
/// middle, and the solid controls footer. Both trays tuck under the input with
/// concave corners, like the nordbones T3 composer.
struct FloatView: View {
    @ObservedObject var chat: ChatState
    let resize: (CGFloat) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var editorHeight: CGFloat = 28
    @State private var composerHeight: CGFloat = 86
    @State private var timelineHeight: CGFloat = 0
    @State private var copiedMessage: String?

    private static let headerHeight: CGFloat = 38
    private static let maxHeight: CGFloat = 560

    private var showsTray: Bool { chat.hasConversation || chat.notice != nil }

    private var panelHeight: CGFloat {
        guard showsTray else { return composerHeight }
        let timeline = chat.hasConversation ? max(56, timelineHeight) : timelineHeight
        return min(Self.maxHeight, composerHeight + Self.headerHeight + timeline)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsTray { tray }
            VStack(spacing: 0) {
                input
                footer
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { composerHeight = ceil($0) }
        }
        .background { shellBackground }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .onAppear { resize(panelHeight) }
        .onChange(of: panelHeight) { _, value in resize(value) }
    }

    @ViewBuilder private var shellBackground: some View {
        if reduceTransparency {
            Theme.surface
        } else {
            ZStack {
                ComposerBackdrop().allowsHitTesting(false).accessibilityHidden(true)
                Theme.raised.opacity(0.55)
            }
        }
    }

    // MARK: Message tray

    private var tray: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if chat.hasOlderMessages {
                        Button("Load older messages", action: chat.loadOlder)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .disabled(chat.loadingOlder)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(chat.messages) { messageView($0) }
                    activity
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { timelineHeight = ceil($0) }
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.never)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
                    Color.black
                }
            }
            .accessibilityLabel("Conversation")
        }
        .background {
            TrayShape(side: .top)
                .fill(Theme.tray.opacity(reduceTransparency ? 0 : 1))
                .padding(.bottom, -Theme.radius)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 6, height: 6).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(chat.title ?? "Float")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .help(chat.title ?? "Float")
                    .accessibilityAddTraits(.isHeader)
                Text(chat.needsT3 ? "T3 not running" : "No project")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
            Spacer(minLength: 8)
            PanelButton("New chat · ⌘N", systemImage: "square.and.pencil", size: 26, action: chat.newChat)
                .disabled(chat.submitting || !chat.hasConversation)
            PanelButton("Open in T3", systemImage: "arrow.up.forward.square", size: 26, action: chat.openThread)
                .disabled(chat.reference?.desktopURL == nil)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: Self.headerHeight)
    }

    private var statusColor: Color {
        if chat.needsT3 { return Theme.muted }
        switch chat.status {
        case .running: return Theme.accent
        case .waiting: return Theme.warning
        case .failed: return Theme.error
        default: return chat.submitting ? Theme.accent : Theme.success
        }
    }

    private var openAction: NoticeAction? {
        chat.reference?.desktopURL == nil ? nil : NoticeAction(title: "Open in T3", handle: { chat.openThread() })
    }

    private var isThinking: Bool { chat.submitting || chat.loading || chat.status == .running }

    @ViewBuilder private var activity: some View {
        if let notice = chat.notice {
            NoticeCard(
                text: notice, tone: chat.needsT3 ? .info : .error,
                action: chat.needsT3 ? NoticeAction(title: "Launch T3", handle: { chat.launchT3() }) : nil
            )
        } else if isThinking {
            ThinkingLoader(size: 16)
                .padding(.leading, 2)
                .padding(.vertical, 4)
        } else if chat.status == .waiting {
            NoticeCard(
                text: "T3 needs your approval or an answer to continue.", tone: .warning,
                action: openAction
            )
        } else if chat.status == .failed {
            NoticeCard(
                text: "The agent run failed.", tone: .error,
                action: openAction
            )
        } else if chat.status == .stopped {
            Text("The agent run stopped.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 2)
        }
    }

    // MARK: Messages

    @ViewBuilder private func messageView(_ message: ChatMessage) -> some View {
        if message.isUser {
            VStack(alignment: .trailing, spacing: 6) {
                if !message.previews.isEmpty { previewRow(message.previews) }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Theme.message, in: UnevenRoundedRectangle(
                            topLeadingRadius: 12, bottomLeadingRadius: 12,
                            bottomTrailingRadius: 4, topTrailingRadius: 12, style: .continuous
                        ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
        } else {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 12, bottomLeadingRadius: 4,
                bottomTrailingRadius: 12, topTrailingRadius: 12, style: .continuous
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(formatted(message.text))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    Spacer(minLength: 0)
                    if let date = message.date {
                        Text(date, style: .time)
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                    PanelButton(
                        copiedMessage == message.id ? "Copied" : "Copy response",
                        systemImage: copiedMessage == message.id ? "checkmark" : "doc.on.doc",
                        size: 22
                    ) { copy(message) }
                }
                .padding(.trailing, -6)
            }
            .padding(.horizontal, 11)
            .padding(.top, 9)
            .padding(.bottom, 3)
            .background(Color.white.opacity(0.035), in: shape)
            .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 1) }
            .padding(.trailing, 24)
        }
    }

    private func copy(_ message: ChatMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        copiedMessage = message.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMessage == message.id { copiedMessage = nil }
        }
    }

    private func previewRow(_ previews: [Data]) -> some View {
        HStack(spacing: 6) {
            ForEach(previews.indices, id: \.self) { index in
                ImagePreview(data: previews[index], label: "Sent image \(index + 1)", size: 64, radius: 8)
            }
        }
    }

    private func formatted(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = .system(size: 12.5, design: .monospaced)
            attributed[run.range].backgroundColor = Theme.code
        }
        return attributed
    }

    // MARK: Input

    private var input: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !chat.images.isEmpty { draftImages }
            ZStack(alignment: .topLeading) {
                if chat.draft.isEmpty {
                    Text(chat.hasConversation ? "Ask a follow-up…" : "Ask anything, or paste a screenshot…")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.placeholder)
                        .padding(.top, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ComposerEditor(
                    text: $chat.draft, height: $editorHeight, focusRequest: chat.focusRequest,
                    submit: chat.send, pasteImages: chat.pasteImages
                )
                .frame(height: editorHeight)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var draftImages: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(chat.images) { file in
                    HStack(spacing: 5) {
                        ImagePreview(data: file.data, label: file.name, size: 18, radius: 4)
                        Text(file.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 104, alignment: .leading)
                        PanelButton("Remove \(file.name)", systemImage: "xmark", size: 16) {
                            chat.removeImage(file.id)
                        }
                    }
                    .padding(.leading, 3)
                    .padding(.trailing, 2)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            PanelButton("Attach images", systemImage: "paperclip", size: 28, action: chooseImages)
            PanelDragHandle()
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .accessibilityHidden(true)
            modelPicker
            sendButton
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .frame(height: 40)
        .background {
            TrayShape(side: .bottom)
                .fill(Theme.tray.opacity(reduceTransparency ? 0 : 1))
                .padding(.top, -Theme.radius)
        }
    }

    private var sendButton: some View {
        Button(action: chat.send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(chat.canSend ? Theme.accent : Theme.muted.opacity(0.7))
                .frame(width: 26, height: 26)
                .overlay {
                    Circle().strokeBorder(chat.canSend ? Theme.accent : Theme.muted.opacity(0.45), lineWidth: 1.5)
                }
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send")
        .help("Send · Return")
        .disabled(!chat.canSend)
    }

    private var modelPicker: some View {
        ModelButton(chat: chat)
            .background(ModelMenuAnchor(chat: chat, request: chat.modelPickerRequest))
            .disabled(!chat.canChooseModel)
            .help("Choose model · ⇧⌘M")
            .accessibilityLabel("Model")
            .accessibilityValue(chat.modelLabel)
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.title = "Attach images"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { result in
            if result == .OK { chat.addImageFiles(panel.urls) }
        }
    }
}

// MARK: - Pieces

private struct ModelButton: View {
    @ObservedObject var chat: ChatState
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    /// "Claude Opus 5.5" reads as "Opus 5.5" next to the Claude mark.
    private var shortLabel: String {
        let label = chat.modelLabel
        return label.hasPrefix("Claude ") ? String(label.dropFirst(7)) : label
    }

    var body: some View {
        Button(action: chat.requestModelPicker) {
            HStack(spacing: 6) {
                ProviderGlyph(instanceId: chat.selectedModel?.instanceId)
                Text(shortLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(enabled ? Theme.text : Theme.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(hovered && enabled ? Color.white.opacity(0.08) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
    }
}

private struct NoticeAction {
    let title: String
    let handle: () -> Void
}

private struct NoticeCard: View {
    enum Tone { case info, warning, error }
    let text: String
    let tone: Tone
    var action: NoticeAction?

    private var tint: Color {
        switch tone {
        case .info: Theme.accent
        case .warning: Theme.warning
        case .error: Theme.error
        }
    }

    private var symbol: String {
        switch tone {
        case .info: "power"
        case .warning: "exclamationmark.shield"
        case .error: "exclamationmark.triangle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                if let action {
                    Button(action: action.handle) {
                        Text(action.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.canvas)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
    }
}

/// Small provider mark for the model control: the Claude burst, or a neutral glyph.
struct ProviderGlyph: View {
    let instanceId: String?

    var body: some View {
        if instanceId == "claudeAgent" {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = size.width / 2 - 0.5, inner = size.width * 0.13
                for i in 0..<8 {
                    let a = Double(i) * .pi / 4
                    var line = Path()
                    line.move(to: CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a)))
                    line.addLine(to: CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a)))
                    context.stroke(line, with: .color(Theme.claude), style: .init(lineWidth: 1.7, lineCap: .round))
                }
            }
            .frame(width: 13, height: 13)
            .accessibilityHidden(true)
        } else {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
    }
}

private struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.toolTip = "Drag to move Float"
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct ComposerBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct ImagePreview: View {
    let data: Data
    let label: String
    let size: CGFloat
    var radius: CGFloat = 6

    var body: some View {
        Group {
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct PanelButton: View {
    let title: String
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    init(_ title: String, systemImage: String, size: CGFloat = 30, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size < 20 ? 9 : size < 26 ? 11 : 13, weight: .medium))
                .foregroundStyle(hovered && enabled ? Theme.text : Theme.muted.opacity(enabled ? 1 : 0.4))
                .frame(width: size, height: size)
                .background(hovered && enabled ? Color.white.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovered = $0 }
    }
}
