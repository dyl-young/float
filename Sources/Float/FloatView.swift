import AppKit
import FloatCore
import SwiftUI
import UniformTypeIdentifiers

/// One shell, three layers: a solid message tray on top, the frosted input in the
/// middle, and the solid controls footer. Both trays tuck under the input with
/// concave corners, like the nordbones T3 composer.
struct FloatView: View {
    @ObservedObject var chat: ChatState
    @ObservedObject var sizing: PanelSizing
    let resize: (CGFloat, Bool, Bool) -> Void
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale
    @State private var editorHeight: CGFloat = 28
    @State private var inputHeight: CGFloat = 44
    @State private var composerHeight: CGFloat = 86
    @State private var timelineHeight: CGFloat = 0
    @State private var timelineBottom: CGFloat = 0
    @State private var inputTop: CGFloat = 0
    @State private var followsLatest = true
    @State private var conversationHover = 0
    @State private var copiedMessage: String?

    private static let headerHeight: CGFloat = 38
    private static let headerFadeHeight: CGFloat = 14
    private static let contextRowHeight: CGFloat = 30
    private nonisolated static let shellSpace = "Float shell"
    private static let latest = "Latest message"
    private static let headerButtonSize: CGFloat = 24
    private static let headerButtonInset: CGFloat = 10
    private static let footerButtonSize: CGFloat = 26
    private static let footerButtonInset: CGFloat = 9
    private static let inputSideInset: CGFloat = 1
    private let inputShape = RoundedRectangle(cornerRadius: Theme.radius)

    private var showsTray: Bool { chat.hasConversation || chat.hasTrayNotice }
    private var showsContextRow: Bool { !chat.hasConversation }

    private var panelHeight: CGFloat {
        let contextHeight = showsContextRow ? Self.contextRowHeight : 0
        guard showsTray else { return composerHeight + contextHeight }
        let timeline = chat.hasConversation ? max(56, timelineHeight) : timelineHeight
        return min(sizing.maximumHeight, composerHeight + Self.headerHeight + timeline) + contextHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            shell
            if showsContextRow { projectContextRow }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .onAppear { resize(panelHeight, showsTray, sizing.isDragging) }
        .onChange(of: panelHeight) { _, value in resize(value, showsTray, sizing.isDragging) }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            if showsTray {
                // Only conversations scroll beneath the frosted input. A notice-only tray
                // keeps its measured bottom gap and sits entirely above the composer.
                tray.padding(.bottom, chat.hasConversation ? -inputHeight : 0)
            }
            VStack(spacing: 0) {
                input
                    .background { inputBackdrop.clipShape(inputShape) }
                    .overlay(alignment: .top) {
                        if showsTray {
                            TrayShape(side: .top)
                                .fill(Theme.tray)
                                .frame(height: Theme.radius)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        inputShape
                            .strokeBorder(Theme.text.opacity(0.09), lineWidth: 1 / displayScale)
                            .allowsHitTesting(false)
                    }
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.shellSpace)) }) {
                        inputHeight = $0.height
                        inputTop = $0.minY
                    }
                    // Keep the input rim separate from the shell border; the footer remains full width.
                    .padding(.horizontal, Self.inputSideInset)
                footer
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { composerHeight = ceil($0) }
        }
        .coordinateSpace(name: Self.shellSpace)
        .background(Theme.tray)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if showsTray {
                PanelResizeHandle(
                    begin: sizing.beginResize,
                    resize: sizing.resize,
                    end: sizing.endResize,
                    reset: sizing.reset
                )
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var projectContextRow: some View {
        HStack(spacing: 0) {
            if chat.showsMachinePicker {
                MachineContextButton(chat: chat)
                    .background(MachineMenuAnchor(chat: chat, request: chat.machinePickerRequest))
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 3)
            }
            ProjectContextButton(chat: chat)
                .background(ProjectMenuAnchor(chat: chat, request: chat.projectPickerRequest))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(height: Self.contextRowHeight, alignment: .top)
    }

    @ViewBuilder private var inputBackdrop: some View {
        if reduceTransparency {
            Theme.raised
        } else {
            ZStack {
                Theme.tray
                if showsTray, timelineBottom > inputTop {
                    // Sample the timeline at its scroll position and blur only the portion under the input.
                    GeometryReader { geometry in
                        timeline
                            .frame(width: geometry.size.width)
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(y: timelineBottom - timelineHeight - inputTop)
                    }
                    .blur(radius: 2.5)
                }
                Theme.raised.opacity(0.55)
                Theme.text.opacity(0.06)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Message tray

    private var tray: some View {
        VStack(spacing: 0) {
            header
            conversation
        }
    }

    private var conversation: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    timeline
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.shellSpace)) }) {
                            let grew = $0.height != timelineHeight
                            timelineHeight = $0.height
                            timelineBottom = $0.maxY
                            if grew, followsLatest, chat.hasConversation {
                                scroll.scrollTo(Self.latest, anchor: .bottom)
                            } else if !grew {
                                followsLatest = timelineBottom <= inputTop + 3
                            }
                        }
                    // Conversations scroll under the composer, so their bottom anchor clears its overlap.
                    // A notice-only tray is already sized to the card and must not scroll it under the header.
                    Color.clear
                        .frame(height: chat.hasConversation ? inputHeight : 0)
                        .id(Self.latest)
                }
            }
            .contentMargins(.trailing, 4, for: .scrollIndicators)
            .contentMargins(.top, 4, for: .scrollIndicators)
            .contentMargins(.bottom, inputHeight + 4, for: .scrollIndicators)
            .scrollIndicators(.visible, axes: .vertical)
            .scrollIndicatorsFlash(trigger: conversationHover)
            .onHover { if $0 { conversationHover += 1 } }
            .onChange(of: inputTop) {
                if followsLatest, chat.hasConversation { scroll.scrollTo(Self.latest, anchor: .bottom) }
                if timelineBottom <= inputTop + 3 { followsLatest = true }
            }
            .onDisappear { followsLatest = true }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.headerFadeHeight)
                    Color.black
                }
            }
            .overlay(alignment: .bottom) {
                if chat.hasConversation, !followsLatest {
                    Button {
                        followsLatest = true
                        scroll.scrollTo(Self.latest, anchor: .bottom)
                    } label: {
                        Text("↓ Latest")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.raised, in: Capsule())
                            .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, inputHeight + 7)
                }
            }
            .accessibilityLabel("Conversation")
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(.top, Self.headerFadeHeight)
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            PanelButton(
                "Close (Esc)", accessibilityLabel: "Close",
                systemImage: "xmark", size: Self.headerButtonSize, glyphSize: 12, action: dismiss
            )
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .help(statusLabel)
                .accessibilityLabel(statusLabel)
            HStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(chat.title ?? "Float")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 4) {
                        if chat.hasThreadProject {
                            Image(systemName: "folder")
                                .font(.system(size: 10, weight: .medium))
                        }
                        Text(chat.threadSubtitle)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
                }
                Spacer(minLength: 8)
            }
            .frame(height: Self.headerHeight)
            .overlay {
                PanelDragHandle().accessibilityHidden(true)
            }
            if chat.hasConversation {
                PanelButton(
                    "New chat · ⌘N", systemImage: "square.and.pencil",
                    size: Self.headerButtonSize, action: chat.newChat
                )
                .disabled(chat.submitting)
                PanelButton(
                    openInT3: "Open in T3",
                    size: Self.headerButtonSize, action: chat.openThread
                )
                .disabled(chat.reference?.desktopURL == nil)
            }
        }
        .padding(.horizontal, Self.headerButtonInset)
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

    private var statusLabel: String {
        if chat.needsT3 { return "T3 not running" }
        switch chat.status {
        case .running: return "Working"
        case .waiting: return "Needs input"
        case .failed: return "Failed"
        default: return chat.submitting ? "Working" : "Ready"
        }
    }

    private var openAction: NoticeAction? {
        chat.reference?.desktopURL == nil ? nil : NoticeAction(
            title: "Open in T3", icon: .openInT3, handle: { chat.openThread() }
        )
    }

    private var isThinking: Bool {
        !chat.stopAcknowledged && (chat.submitting || chat.loading || chat.status == .running)
    }

    @ViewBuilder private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = chat.notice, chat.noticeKind != .input {
                NoticeCard(
                    title: chat.noticeTitle,
                    text: notice,
                    detail: chat.noticeDetail,
                    tone: chat.needsT3 ? .info : .error,
                    action: chat.canLaunchT3
                        ? NoticeAction(title: "Launch T3", handle: { chat.launchT3() })
                        : chat.noticeKind == .run ? openAction : nil,
                    secondaryAction: chat.canLaunchT3
                        ? NoticeAction(title: "Not now", handle: { chat.dismissNotice() })
                        : nil,
                    dismiss: chat.dismissNotice
                )
            }
            if isThinking {
                ThinkingLoader(size: 16)
                    .padding(.leading, 2)
                    .padding(.vertical, 4)
            } else if chat.status == .waiting, !chat.statusNoticeDismissed {
                NoticeCard(
                    text: "T3 needs your approval or an answer to continue.", tone: .warning,
                    action: openAction, dismiss: chat.dismissNotice
                )
            } else if chat.status == .failed, !chat.statusNoticeDismissed {
                NoticeCard(
                    text: ["The agent run failed.", chat.failureReason].compactMap { $0 }.joined(separator: " "),
                    detail: chat.failureDetail,
                    tone: .error,
                    action: openAction,
                    dismiss: chat.dismissNotice
                )
            } else if chat.status == .stopped || chat.stopAcknowledged {
                Text("Stopped")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 4) {
                MarkdownReply(text: message.text)
                HStack(spacing: 6) {
                    Button { copy(message) } label: {
                        Image(systemName: copiedMessage == message.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 12, height: 22, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(copiedMessage == message.id ? "Copied" : "Copy response")
                    .accessibilityLabel(copiedMessage == message.id ? "Copied" : "Copy response")
                    if let date = message.date {
                        Text(date, style: .time)
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        RightAlignedFlowLayout(spacing: 6) {
            ForEach(previews.indices, id: \.self) { index in
                ImagePreview(data: previews[index], label: "Sent image \(index + 1)", size: 64, radius: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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
            if let notice = chat.notice, chat.noticeKind == .input {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(chat.noticeDetail ?? notice)
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
            PanelButton("Attach images", systemImage: "paperclip", size: Self.footerButtonSize, action: chooseImages)
                .offset(y: -1)
            PanelDragHandle()
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .accessibilityHidden(true)
            modelPicker
            sendButton
        }
        .padding(.horizontal, Self.footerButtonInset)
        .frame(height: 40)
        .background {
            TrayShape(side: .bottom)
                .fill(Theme.tray)
                .padding(.top, -Theme.radius)
        }
    }

    private var sendButton: some View {
        let stopping = chat.showsStop
        let tint = stopping ? Theme.error : chat.canSend ? Theme.accent : Theme.muted
        let enabled = stopping ? chat.canStop : chat.canSend
        return Button {
            if stopping {
                chat.stop()
            } else {
                chat.send()
            }
        } label: {
            sendGlyph(stopping: stopping)
                .foregroundStyle(tint.opacity(stopping || chat.canSend ? 1 : 0.7))
                .frame(width: Self.footerButtonSize, height: Self.footerButtonSize)
                .overlay {
                    Circle().strokeBorder(tint.opacity(stopping || chat.canSend ? 1 : 0.45), lineWidth: 1.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stopping ? "Stop" : "Send")
        .help(stopping ? "Stop · ⌘." : "Send · Return")
        .disabled(!enabled)
    }

    @ViewBuilder private func sendGlyph(stopping: Bool) -> some View {
        if stopping {
            RoundedRectangle(cornerRadius: 2).frame(width: 8, height: 8)
        } else {
            Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
        }
    }

    private var modelPicker: some View {
        ModelButton(chat: chat)
            .background(ModelMenuAnchor(chat: chat, request: chat.modelPickerRequest))
            .disabled(!chat.canChooseModel)
            .help("Choose model · ⇧⌘M")
            .accessibilityLabel("Model")
            .accessibilityValue(chat.modelCatalogFailed ? "Models unavailable" : chat.modelLabel)
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

private struct MarkdownReply: View {
    let text: String

    var body: some View {
        let blocks = MarkdownBlockParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { index in
                block(blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func block(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
        case .heading(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 13.5, weight: .semibold))
                .lineSpacing(3)
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .textSelection(.enabled)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    listRow(marker: "•", text: items[index])
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    listRow(marker: "\(items[index].number).", text: items[index].text)
                }
            }
        case .code(let language, let text):
            MarkdownCodeBlock(language: language, text: text)
        }
    }

    private func inlineText(_ text: String) -> some View {
        Text(inlineMarkdown(text))
            .font(.system(size: 13.5))
            .lineSpacing(3)
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.muted)
                .frame(width: 20, alignment: .trailing)
            inlineText(text)
        }
    }
}

private struct MarkdownCodeBlock: View {
    let language: String?
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language {
                Text(language)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.trailing, 24)
            }
            .scrollIndicators(.visible)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.code, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, height: 22)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(copied ? "Copied" : "Copy code")
            .accessibilityLabel(copied ? "Copied" : "Copy code")
            .padding(6)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private func inlineMarkdown(_ text: String) -> AttributedString {
    var attributed = (try? AttributedString(
        markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
    for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
        attributed[run.range].font = .system(size: 12.5, design: .monospaced)
        attributed[run.range].backgroundColor = Theme.code
    }
    return attributed
}

private struct RightAlignedFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = layout(subviews, width: bounds.width)
        for row in result.rows {
            var x = bounds.maxX - row.width
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
        }
    }

    private func layout(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, rows: [Row]) {
        var rows: [Row] = []
        var row = Row()
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if nextWidth > width, !row.items.isEmpty {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.items.append(Item(subview: subview, size: size))
            row.width = row.items.count == 1 ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return (
            CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0),
            rows
        )
    }

    private struct Item {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }
}

private struct ModelButton: View {
    @ObservedObject var chat: ChatState
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        Button(action: chat.requestModelPicker) {
            HStack(alignment: .center, spacing: 6) {
                if chat.modelCatalogFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warning)
                } else {
                    ProviderGlyph(driverKind: chat.selectedCatalogModel?.driverKind ?? chat.selectedModel?.instanceId)
                }
                Text(chat.modelCatalogFailed ? "Models unavailable" : chat.selectedCatalogModel?.shortLabel ?? chat.modelLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chat.modelCatalogFailed ? Theme.muted : enabled ? Theme.text : Theme.muted)
                if !chat.modelCatalogFailed {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .offset(y: -0.5)
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

private struct ProjectContextButton: View {
    @ObservedObject var chat: ChatState
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        Button(action: chat.requestProjectPicker) {
            HStack(spacing: 5) {
                Image(systemName: chat.selectedProject == nil ? "pencil" : "folder")
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(width: 12)
                Text(chat.projectLabel)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(enabled ? Theme.muted : Theme.muted.opacity(0.5))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(hovered && enabled ? Theme.text.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!chat.canChooseProject)
        .help("Choose project · ⇧⌘P")
        .accessibilityLabel("Project")
        .accessibilityValue(chat.projectLabel)
        .onHover { hovered = $0 }
    }
}

private struct MachineContextButton: View {
    @ObservedObject var chat: ChatState
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        Button(action: chat.requestMachinePicker) {
            HStack(spacing: 5) {
                Image(systemName: chat.selectedMachine?.isLocal == false ? "server.rack" : "laptopcomputer")
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(width: 12)
                Text(chat.machineLabel)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(enabled ? Theme.muted : Theme.muted.opacity(0.5))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                hovered && enabled ? Theme.text.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!chat.canChooseMachine)
        .help("Choose machine · ⇧⌘R")
        .accessibilityLabel("Run on")
        .accessibilityValue(chat.machineLabel)
        .onHover { hovered = $0 }
    }
}

private struct NoticeAction {
    enum Icon { case openInT3 }
    let title: String
    var icon: Icon?
    let handle: () -> Void

    init(title: String, icon: Icon? = nil, handle: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.handle = handle
    }
}

private struct NoticeCard: View {
    enum Tone { case info, warning, error }
    var title: String?
    let text: String
    var detail: String?
    let tone: Tone
    var action: NoticeAction?
    var secondaryAction: NoticeAction?
    let dismiss: () -> Void

    init(
        title: String? = nil, text: String, detail: String? = nil, tone: Tone,
        action: NoticeAction? = nil, secondaryAction: NoticeAction? = nil,
        dismiss: @escaping () -> Void
    ) {
        self.title = title
        self.text = text
        self.detail = detail
        self.tone = tone
        self.action = action
        self.secondaryAction = secondaryAction
        self.dismiss = dismiss
    }

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
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    Text(text)
                        .font(.system(size: title == nil ? 12.5 : 12))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if action != nil || secondaryAction != nil {
                    HStack(spacing: 6) {
                        if let action {
                            noticeButton(action, primary: true)
                        }
                        if let secondaryAction {
                            noticeButton(secondaryAction, primary: false)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if secondaryAction == nil {
                PanelButton("Dismiss", systemImage: "xmark", size: 18, action: dismiss)
                    .offset(x: 3, y: -3)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
        .help(detail ?? text)
    }

    private func noticeButton(_ action: NoticeAction, primary: Bool) -> some View {
        Button(action: action.handle) {
            HStack(spacing: 5) {
                if action.icon == .openInT3 {
                    OpenInT3Glyph(size: 12)
                }
                Text(action.title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(primary ? Theme.canvas : Theme.muted)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(primary ? tint : Color.clear, in: Capsule())
            .overlay {
                if !primary {
                    Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
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

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct PanelResizeHandle: NSViewRepresentable {
    let begin: () -> Void
    let resize: (CGFloat) -> Void
    let end: () -> Void
    let reset: () -> Void

    func makeNSView(context: Context) -> ResizeView {
        let view = ResizeView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ResizeView, context: Context) {
        view.begin = begin
        view.resize = resize
        view.end = end
        view.reset = reset
    }

    static func dismantleNSView(_ view: ResizeView, coordinator: ()) {
        view.finishResize()
    }

    final class ResizeView: NSView {
        var begin: (() -> Void)?
        var resize: ((CGFloat) -> Void)?
        var end: (() -> Void)?
        var reset: (() -> Void)?
        private var startY: CGFloat?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                reset?()
                return
            }
            startY = NSEvent.mouseLocation.y
            begin?()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startY else { return }
            resize?(NSEvent.mouseLocation.y - startY)
        }

        override func mouseUp(with event: NSEvent) {
            finishResize()
        }

        func finishResize() {
            guard startY != nil else { return }
            startY = nil
            end?()
        }
    }
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
    private enum Glyph {
        case system(String)
        case openInT3
    }

    let title: String
    let accessibilityTitle: String
    private let glyph: Glyph
    let size: CGFloat
    let glyphSize: CGFloat?
    let action: () -> Void

    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    init(
        _ title: String, accessibilityLabel: String? = nil,
        systemImage: String, size: CGFloat = 30, glyphSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        accessibilityTitle = accessibilityLabel ?? title
        glyph = .system(systemImage)
        self.size = size
        self.glyphSize = glyphSize
        self.action = action
    }

    init(
        openInT3 title: String, accessibilityLabel: String? = nil,
        size: CGFloat = 30, glyphSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        accessibilityTitle = accessibilityLabel ?? title
        glyph = .openInT3
        self.size = size
        self.glyphSize = glyphSize
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            glyphView
                .foregroundStyle(hovered && enabled ? Theme.text : Theme.muted.opacity(enabled ? 1 : 0.4))
                .frame(width: size, height: size)
                .background(hovered && enabled ? Color.white.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(accessibilityTitle)
        .onHover { hovered = $0 }
    }

    @ViewBuilder private var glyphView: some View {
        let iconSize = glyphSize ?? (size < 20 ? 9 : size < 26 ? 11 : 13)
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: iconSize, weight: .medium))
        case .openInT3:
            OpenInT3Glyph(size: iconSize)
        }
    }
}

private struct OpenInT3Glyph: View {
    let size: CGFloat

    var body: some View {
        OpenInT3Shape()
            .stroke(style: StrokeStyle(
                lineWidth: max(1, size / 10), lineCap: .round, lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}
