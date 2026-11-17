import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FloatPalette {
    static let canvas = Color(red: 0.067, green: 0.100, blue: 0.125)
    static let composer = Color(red: 0.073, green: 0.115, blue: 0.145)
    static let footer = Color(red: 0.096, green: 0.145, blue: 0.177)
    static let raised = Color(red: 0.135, green: 0.206, blue: 0.250)
    static let border = Color(red: 0.63, green: 0.76, blue: 0.86).opacity(0.16)
    static let text = Color(red: 0.90, green: 0.95, blue: 0.99)
    static let muted = Color(red: 0.59, green: 0.67, blue: 0.74)
    static let accent = Color(red: 0.42, green: 0.69, blue: 0.91)
}

struct FloatView: View {
    @ObservedObject var chat: ChatState
    let resize: (CGFloat) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var editorHeight: CGFloat = 28
    @State private var composerHeight: CGFloat = 79
    @State private var timelineHeight: CGFloat = 0
    @State private var feedbackHeight: CGFloat = 0
    @State private var copiedMessage: String?

    private var panelHeight: CGFloat {
        guard chat.hasConversation else { return composerHeight }
        let controlsHeight = composerHeight + 46 + feedbackHeight
        return min(536, controlsHeight + max(68, timelineHeight))
    }

    var body: some View {
        VStack(spacing: 7) {
            if chat.hasConversation { conversation }
            composer
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { composerHeight = ceil($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear { resize(panelHeight) }
        .onChange(of: panelHeight) { _, value in resize(value) }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let title = chat.title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FloatPalette.text)
                        .lineLimit(1)
                        .help(title)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                action("New Chat", chat.newChat).disabled(chat.submitting).help("New Chat · ⌘N")
                action("Open in T3", chat.openThread).disabled(chat.reference?.desktopURL == nil)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 15)
            .frame(height: 38)
            Rectangle().fill(FloatPalette.border).frame(height: 1).padding(.horizontal, 14)
            timeline
            VStack(spacing: 0) {
                if let notice = chat.notice {
                    noticeBar(notice)
                } else {
                    statusBar
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { feedbackHeight = ceil($0) }
        }
        .background(FloatPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(FloatPalette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                if chat.hasOlderMessages {
                    Button("Load older messages", action: chat.loadOlder)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FloatPalette.accent)
                        .disabled(chat.loadingOlder)
                        .frame(maxWidth: .infinity)
                }
                ForEach(chat.messages) { message in
                    messageView(message)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { timelineHeight = ceil($0) }
        }
        .defaultScrollAnchor(.bottom)
        .accessibilityLabel("Conversation")
    }

    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 7) {
            if !message.previews.isEmpty {
                ViewThatFits(in: .horizontal) {
                    previewRow(message.previews)
                    ScrollView(.horizontal) { previewRow(message.previews) }
                }
            }
            if !message.text.isEmpty {
                Text(formatted(message))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(FloatPalette.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(message.isUser ? FloatPalette.raised : FloatPalette.composer,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityLabel(message.text)
            }
            if !message.isUser {
                HStack(spacing: 8) {
                    PanelButton(
                        copiedMessage == message.id ? "Copied" : "Copy response",
                        systemImage: copiedMessage == message.id ? "checkmark" : "document.on.document",
                        size: 22
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        copiedMessage = message.id
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            if copiedMessage == message.id { copiedMessage = nil }
                        }
                    }
                    if let date = message.date {
                        Text(date, style: .time)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(FloatPalette.muted)
                    }
                }
                .padding(.leading, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private func previewRow(_ previews: [Data]) -> some View {
        HStack(spacing: 6) {
            ForEach(previews.indices, id: \.self) { index in
                ImagePreview(data: previews[index], label: "Sent image \(index + 1)", size: 76)
            }
        }
    }

    private func formatted(_ message: ChatMessage) -> AttributedString {
        guard !message.isUser else { return AttributedString(message.text) }
        return (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
    }

    @ViewBuilder private var statusBar: some View {
        if chat.submitting || chat.loading || chat.status == .running {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.76)
                Text(chat.submitting ? "Sending…" : chat.loading ? "Loading chat…" : "Waiting for a reply…")
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(FloatPalette.muted)
            .padding(.horizontal, 17)
            .padding(.vertical, 7)
        } else if chat.status == .waiting || chat.status == .failed || chat.status == .stopped {
            HStack(spacing: 8) {
                Text(chat.status == .waiting ? "T3 needs your input." :
                    chat.status == .failed ? "The agent run failed." : "The agent run stopped.")
                    .foregroundStyle(FloatPalette.muted)
                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 17)
            .padding(.vertical, 7)
        }
    }

    private func noticeBar(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            if chat.needsT3 { action("Launch T3", chat.launchT3) }
        }
        .font(.system(size: 12))
        .foregroundStyle(FloatPalette.muted)
        .padding(.horizontal, 17)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
    }

    private func action(_ title: String, _ handle: @escaping () -> Void) -> some View {
        Button(title, action: handle)
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(FloatPalette.accent)
            .fixedSize()
    }

    private var composer: some View {
        let radius: CGFloat = 17
        let footerHeight: CGFloat = 36
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    if !chat.images.isEmpty { draftImages }
                    ZStack(alignment: .topLeading) {
                        if chat.draft.isEmpty {
                            Text(chat.hasConversation ? "Follow up…" : "Ask or start a task…")
                                .font(.system(size: 14))
                                .foregroundStyle(FloatPalette.muted)
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
                .padding(.top, 8)
                .padding(.horizontal, 13)
                .padding(.bottom, 7)

                if !chat.hasConversation, let notice = chat.notice { noticeBar(notice) }
            }
            .background(FloatPalette.composer.opacity(reduceTransparency ? 1 : 0.62), in: shape)

            HStack(spacing: 6) {
                PanelButton("Attach images", systemImage: "paperclip", action: chooseImages)
                PanelDragHandle()
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .accessibilityHidden(true)
                modelPicker
                Button(action: chat.send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(chat.canSend ? FloatPalette.accent : FloatPalette.muted.opacity(0.62))
                        .frame(width: 24, height: 24)
                        .background {
                            Circle().strokeBorder(
                                chat.canSend ? FloatPalette.accent.opacity(0.85) : FloatPalette.border,
                                lineWidth: 1
                            )
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
                .help("Send · Return")
                .disabled(!chat.canSend)
            }
            .padding(.leading, 7)
            .padding(.trailing, 8)
            .frame(height: footerHeight)
        }
        .background {
            ZStack {
                if !reduceTransparency {
                    ComposerBackdrop(radius: radius)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                shape.fill(FloatPalette.footer.opacity(reduceTransparency ? 1 : 0.42))
                if !reduceTransparency {
                    Canvas { context, size in
                        let bounds = CGRect(origin: .zero, size: size)
                        let footerTop = bounds.height - footerHeight
                        let inputBounds = CGRect(x: 0, y: 0, width: bounds.width, height: footerTop)
                        let footerBounds = CGRect(
                            x: 0, y: inputBounds.midY, width: bounds.width, height: bounds.height - inputBounds.midY
                        )
                        // Continue the footer tint through the cutouts around the input corners.
                        var outsideInput = Path(bounds)
                        outsideInput.addPath(shape.path(in: inputBounds))
                        context.clip(to: outsideInput, style: FillStyle(eoFill: true))
                        context.fill(Path(footerBounds), with: .color(FloatPalette.footer.opacity(0.44)))
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(FloatPalette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var modelPicker: some View {
        Button(action: chat.requestModelPicker) {
            HStack(spacing: 4) {
                Text(chat.modelLabel).font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(FloatPalette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.055), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background(ModelMenuAnchor(chat: chat, request: chat.modelPickerRequest))
        .disabled(!chat.canChooseModel)
        .help("Choose model · ⇧⌘M")
        .accessibilityLabel("Model")
        .accessibilityValue(chat.modelLabel)
    }

    private var draftImages: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(chat.images) { file in
                    HStack(spacing: 6) {
                        ImagePreview(data: file.data, label: file.name, size: 30)
                        Text(file.name)
                            .font(.system(size: 11))
                            .foregroundStyle(FloatPalette.text)
                            .lineLimit(1)
                            .frame(maxWidth: 110, alignment: .leading)
                        PanelButton("Remove \(file.name)", systemImage: "xmark", size: 22) {
                            chat.removeImage(file.id)
                        }
                    }
                    .padding(3)
                    .background(FloatPalette.raised, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
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
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct ImagePreview: View {
    let data: Data
    let label: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(FloatPalette.muted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                .font(.system(size: size < 26 ? 11 : 13, weight: .medium))
                .foregroundStyle(FloatPalette.muted.opacity(enabled ? 1 : 0.4))
                .frame(width: size, height: size)
                .background(hovered && enabled ? FloatPalette.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovered = $0 }
    }
}
