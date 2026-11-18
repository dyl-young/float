import AppKit
import FloatCore
import SwiftUI
import UniformTypeIdentifiers

/// One shell, three layers: a solid message tray on top, the frosted input in the
/// middle, and the solid controls footer. Both trays tuck under the input with
/// concave corners, like the nordbones T3 composer.
struct FloatView: View {
    @ObservedObject var chat: ChatState
    let resize: (CGFloat, Bool) -> Void
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale
    @State private var isMachinePickerOpen = false
    @State private var isProjectPickerOpen = false
    @State private var editorHeight: CGFloat = 28
    @State private var inputHeight: CGFloat = 44
    @State private var composerHeight: CGFloat = 86
    @State private var nonConversationHeight: CGFloat?
    @State private var timelineHeight: CGFloat = 0
    @State private var timelineBottom: CGFloat = 0
    @State private var inputTop: CGFloat = 0
    @State private var followsLatest = true
    @State private var copiedMessage: String?

    private static let headerHeight: CGFloat = 38
    private static let headerFadeHeight: CGFloat = 14
    private static let contextGap: CGFloat = 6
    private static let contextShadowBottom: CGFloat = 36
    private static let contextPadding: CGFloat = 3
    private static let contextBorderWidth: CGFloat = 1
    static let contextShadowSides: CGFloat = 26
    static let contextRowHeight = contextGap + ContextChip.height
        + 2 * (contextPadding + contextBorderWidth) + contextShadowBottom
    private nonisolated static let shellSpace = "Float shell"
    private static let latest = "Latest message"
    private static let headerButtonSize: CGFloat = 24
    private static let headerButtonInset: CGFloat = 10
    private static let footerButtonSize: CGFloat = 26
    private static let footerButtonInset: CGFloat = 9
    private static let inputSideInset: CGFloat = 1
    private let inputShape = RoundedRectangle(cornerRadius: Theme.radius)

    private var showsTray: Bool { chat.hasConversation || chat.hasTrayNotice }
    private var showsContextRow: Bool { !showsTray }

    private var compactHeight: CGFloat {
        nonConversationHeight ?? composerHeight + Self.contextRowHeight
    }

    var body: some View {
        let trayVisible = showsTray
        VStack(alignment: .leading, spacing: 0) {
            shell
            if showsContextRow { contextStrip }
        }
        .padding(.horizontal, trayVisible ? 0 : Self.contextShadowSides)
        .fixedSize(horizontal: false, vertical: !trayVisible)
        .onGeometryChange(for: CGFloat?.self, of: { geometry in
            trayVisible ? nil : ceil(geometry.size.height)
        }) { height in
            if let height { nonConversationHeight = height }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .onChange(of: trayVisible, initial: true) { resize(compactHeight, trayVisible) }
        .onChange(of: compactHeight) {
            if !trayVisible { resize(compactHeight, false) }
        }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            if showsTray { header }
            if chat.hasConversation {
                conversation.padding(.bottom, -inputHeight)
            } else if chat.hasTrayNotice {
                noticeCard
                    .padding(14)
                Spacer(minLength: 0)
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
                    .overlay(alignment: .top) {
                        PanelDragHandle()
                            .frame(height: 6)
                            .accessibilityHidden(true)
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
        .frame(maxWidth: .infinity)
    }

    private var contextStrip: some View {
        let strip = RoundedRectangle(cornerRadius: 12)
        return HStack(spacing: 4) {
            if chat.showsMachinePicker {
                ContextChip(
                    title: chat.machineLabel,
                    icon: chat.selectedMachine?.isLocal == false ? "server.rack" : "laptopcomputer",
                    isOpen: isMachinePickerOpen,
                    action: chat.requestMachinePicker
                )
                .disabled(!chat.canChooseMachine)
                .help("Choose machine · ⇧⌘H")
                .accessibilityLabel("Run on")
                .accessibilityValue(chat.machineLabel)
                .background(MachineMenuAnchor(
                    chat: chat, request: chat.machinePickerRequest, isPresented: $isMachinePickerOpen
                ))
            }

            ContextChip(
                title: chat.projectLabel,
                icon: chat.selectedProject == nil ? "pencil" : "folder",
                isOpen: isProjectPickerOpen,
                action: chat.requestProjectPicker
            )
            .disabled(!chat.canChooseProject)
            .help("Choose project · ⇧⌘P")
            .accessibilityLabel("Project")
            .accessibilityValue(chat.projectLabel)
            .background(ProjectMenuAnchor(
                chat: chat, request: chat.projectPickerRequest, isPresented: $isProjectPickerOpen
            ))
        }
        .padding(Self.contextPadding + Self.contextBorderWidth)
        .background {
            ZStack {
                // The mockup's shadow has a negative spread. Inset its source
                // shape while keeping the strip fill and border at full size.
                strip.inset(by: 12)
                    .fill(Theme.tray)
                    .shadow(color: Theme.canvas.opacity(0.55), radius: 13, y: 10)
                if !reduceTransparency {
                    ContextStripBlur().clipShape(strip)
                }
                strip.fill(Theme.tray.opacity(reduceTransparency ? 1 : 0.94))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay {
            strip.strokeBorder(Theme.hairline, lineWidth: Self.contextBorderWidth)
                .allowsHitTesting(false)
        }
        .padding(.top, Self.contextGap)
        .padding(.bottom, Self.contextShadowBottom)
    }

    @ViewBuilder private var inputBackdrop: some View {
        if reduceTransparency {
            Theme.raised
        } else {
            ZStack {
                Theme.tray
                if chat.hasConversation, timelineBottom > inputTop {
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
                    // The bottom anchor clears the composer's overlap.
                    Color.clear
                        .frame(height: inputHeight)
                        .id(Self.latest)
                }
                .background(OverlayScrollers())
            }
            .contentMargins(.trailing, 4, for: .scrollIndicators)
            .contentMargins(.top, 4, for: .scrollIndicators)
            .contentMargins(.bottom, inputHeight + 4, for: .scrollIndicators)
            .flashScrollKnobsOnHover()
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
                    .floatButtonStyle(in: Capsule())
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
                    .floatButtonStyle()
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .disabled(chat.loadingOlder)
                    .frame(maxWidth: .infinity)
            }
            ForEach(chat.groupedMessages) { messageView($0) }
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
            HStack(spacing: 7) {
                if let offlineLabel {
                    Circle()
                        .fill(Theme.muted)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    .help(offlineLabel)
                }
                if let project = chat.threadProjectLabel {
                    HStack(spacing: 5) {
                        HeaderProjectIcon(project: chat.threadProject, isLocal: chat.threadHeaderEnvironmentID == nil)
                        Text(chat.threadMachineName.map { "\(project) · \($0)" } ?? project)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 210, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    Text("/")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted.opacity(0.55))
                }
                headerTitle(chat.title ?? "Float")
                if !chat.hasConversation, let offlineLabel {
                    Text(offlineLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .frame(height: Self.headerHeight)
            .overlay {
                PanelDragHandle()
                    .padding(.top, 10)
                    .accessibilityHidden(true)
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
        .task(id: chat.threadProjectLookup) { await chat.loadThreadProject() }
    }

    private func headerTitle(_ title: String) -> some View {
        Text(verbatim: ChatTitle.plainText(title))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }

    private var offlineLabel: String? {
        if chat.needsT3 { return "T3 not running" }
        if chat.threadMachineDisconnected {
            return "\(chat.threadMachineName ?? "Thread machine") is offline"
        }
        return nil
    }

    private var openAction: NoticeAction? {
        chat.reference?.desktopURL == nil ? nil : NoticeAction(
            title: "Open in T3", icon: .openInT3, handle: { chat.openThread() }
        )
    }

    private var isThinking: Bool {
        !chat.stopAcknowledged && (chat.submitting || chat.loading || chat.status == .running)
    }

    @ViewBuilder private var noticeCard: some View {
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
    }

    @ViewBuilder private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            noticeCard
            if let summary = chat.answeredQuestionSummary, !summary.isEmpty {
                Text("Answered: \(summary)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .help(summary)
                    .padding(.leading, 2)
                    .padding(.bottom, chat.activeQuestion == nil ? 0 : 4)
            }
            if let summary = chat.approvalSummary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .help(summary)
                    .padding(.leading, 2)
            }
            if let question = chat.activeQuestion, let request = chat.pendingQuestion {
                QuestionCard(
                    chat: chat, request: request, question: question, position: chat.questionIndex + 1
                )
                .id("\(request.requestId):\(question.id)")
            } else if chat.activeApproval != nil || chat.approvalPreview != nil {
                approvalCard
            } else if isThinking {
                ThinkingActivity(startedAt: chat.thinkingStartedAt)
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

    private var approvalCard: ApprovalCard {
        let canOptIn = chat.reference?.environmentID == nil && !chat.approvalAccessEnabled
        let optIn: (() -> Void)? = canOptIn ? { chat.enableApprovals() } : nil
        let open: (() -> Void)? = chat.reference?.desktopURL == nil ? nil : { chat.openThread() }
        return ApprovalCard(request: chat.activeApproval, count: chat.pendingApprovals.count,
                            preview: chat.approvalPreview, optIn: optIn,
                            busy: chat.stopping || chat.approvalAccessBusy || chat.respondingToApproval,
                            error: chat.approvalError ?? chat.approvalAccessError, openInT3: open,
                            respond: chat.respondToApproval)
    }

    // MARK: Messages

    @ViewBuilder private func messageView(_ message: ChatMessage) -> some View {
        if message.isUser {
            VStack(alignment: .trailing, spacing: 6) {
                if !message.previews.isEmpty { previewRow(message.previews) }
                if !message.text.isEmpty {
                    MessageMarkdown(source: message.text, isUser: true)
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
                MessageMarkdown(source: message.text)
                HStack(spacing: 6) {
                    Button { copy(message) } label: {
                        Image(systemName: copiedMessage == message.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 12, height: 22, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .floatButtonStyle()
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
                if chat.composerText.isEmpty {
                    Text(chat.composerPlaceholder)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.placeholder)
                        .padding(.top, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ComposerEditor(
                    text: Binding(get: { chat.composerText }, set: chat.setComposerText),
                    height: $editorHeight, focusRequest: chat.focusRequest,
                    editable: chat.composerEditable, submit: chat.confirmOrSend,
                    pickOption: chat.selectQuestionOption(at:), pasteImages: chat.pasteImages
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
            .background(OverlayScrollers())
        }
        .flashScrollKnobsOnHover()
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
                .foregroundStyle(tint)
                .frame(width: Self.footerButtonSize, height: Self.footerButtonSize)
                .overlay {
                    Circle().strokeBorder(tint, lineWidth: 1.5)
                }
                .contentShape(Rectangle())
        }
        .floatButtonStyle(in: Circle())
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

struct MarkdownCodeBlock: View {
    let language: String?
    let text: String
    @State private var wrapped = true
    @State private var copied = false

    private var languageIcon: NSImage? {
        guard let language else { return nil }
        let asset: String
        switch language.lowercased() {
        case "swift", "html", "css", "json", "go": asset = language.lowercased()
        case "python", "py": asset = "python"
        case "javascript", "js", "jsx", "mjs", "cjs": asset = "javascript"
        case "typescript", "ts", "tsx": asset = "typescript"
        case "shell", "shellscript", "bash", "sh", "zsh", "fish": asset = "shell"
        case "markdown", "md", "mdx": asset = "markdown"
        case "yaml", "yml": asset = "yaml"
        case "rust", "rs": asset = "rust"
        default: return nil
        }
        guard let url = Bundle.main.url(forResource: asset, withExtension: "svg", subdirectory: "languages") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let language, let languageIcon {
                    Image(nsImage: languageIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .accessibilityLabel(language)
                        .help(language)
                } else if let language {
                    Text(language)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                PanelButton(wrapped ? "Disable line wrap" : "Wrap lines",
                            systemImage: "text.line.last.and.arrowtriangle.forward", size: 20) {
                    wrapped.toggle()
                }
                PanelButton(copied ? "Copied" : "Copy code",
                            systemImage: copied ? "checkmark" : "doc.on.doc", size: 20, action: copy)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 26)
            if wrapped {
                code.fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal) {
                    code
                        .fixedSize(horizontal: true, vertical: true)
                        .background(OverlayScrollers())
                }
                .flashScrollKnobsOnHover()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.border.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var code: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.text)
            .textSelection(.enabled)
            .lineSpacing(3)
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 10)
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
            .contentShape(Capsule())
        }
        .floatButtonStyle(in: Capsule())
        .fixedSize()
    }
}

private struct ContextChip: View {
    static let height: CGFloat = 22

    let title: String
    let icon: String
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        let pill = RoundedRectangle(cornerRadius: 9)
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.system(size: 11.5, weight: .regular))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .regular))
                    .frame(width: 9, height: 9)
                    .opacity(0.7)
            }
            .foregroundStyle(isOpen ? Theme.text : Theme.muted)
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background(isOpen ? Theme.selection : .clear, in: pill)
            .contentShape(pill)
        }
        .floatButtonStyle(in: pill, highlight: isOpen ? .none : .background)
    }
}

private struct ContextStripBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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

private struct QuestionCard: View {
    @ObservedObject var chat: ChatState
    let request: T3PendingQuestionRequest
    let question: T3Question
    let position: Int

    @State private var showingSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(verbatim: question.header)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if request.questions.count > 1 { stepMenu }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .padding(.bottom, 5)

            Text(verbatim: question.question)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                optionRow(option, index: index)
            }

            if let error = chat.questionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            HStack(spacing: 6) {
                if position > 1 {
                    Button("Back") { chat.goBackQuestion() }
                        .floatPillButtonStyle(tint: nil)
                        .disabled(chat.stopping || chat.answeringQuestion)
                        .help("Back · ⌘[")
                }
                Button(chat.isLastQuestion ? "Send answer" : "Next", action: chat.confirmQuestion)
                    .floatPillButtonStyle()
                    .disabled(chat.stopping || !chat.questionCanAdvance || chat.answeringQuestion)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Theme.text.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question.header)
    }

    private var stepMenu: some View {
        Button {
            if !chat.closeQuestionSteps() {
                let presentation = $showingSteps
                chat.dismissQuestionSteps = { presentation.wrappedValue = false }
                showingSteps = true
            }
        } label: {
            HStack(spacing: 3) {
                Text("\(position)/\(request.questions.count)")
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .floatButtonStyle()
        .disabled(chat.stopping || chat.answeringQuestion)
        .accessibilityLabel("Jump to question")
        .accessibilityValue("\(position) of \(request.questions.count)")
        .popover(isPresented: $showingSteps, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(request.questions.enumerated()), id: \.offset) { index, step in
                        stepRow(step, index: index)
                    }
                }
                .padding(4)
                .background(OverlayScrollers())
            }
            .frame(width: 220, height: CGFloat(min(request.questions.count, 8) * 28 + 6))
            .background(Theme.raised)
            .preferredColorScheme(.dark)
            .onExitCommand { chat.closeQuestionSteps() }
        }
        .onChange(of: showingSteps) {
            if !showingSteps { chat.dismissQuestionSteps = nil }
        }
        .onDisappear {
            if showingSteps { chat.closeQuestionSteps() }
        }
    }

    private func stepRow(_ step: T3Question, index: Int) -> some View {
        let selected = index == position - 1
        return Button {
            showingSteps = false
            chat.jumpToQuestion(index)
        } label: {
            Text("\(index + 1). \(step.header)")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .floatButtonStyle(in: RoundedRectangle(cornerRadius: 8))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionRow(_ option: T3Question.Option, index: Int) -> some View {
        let selected = chat.isQuestionOptionSelected(option)
        let description = option.displayDescription
        let row = RoundedRectangle(cornerRadius: 7)
        return Button {
            chat.selectQuestionOption(option)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                selectionMark(selected: selected)
                    .frame(width: 13, height: 13)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: option.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description {
                        Text(verbatim: description)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let preview = option.preview, !preview.isEmpty {
                        Text(verbatim: preview)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: true, vertical: true)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .clipped()
                            .padding(.top, 5)
                            .padding(.bottom, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Theme.text)
                        .frame(width: 18, height: 18)
                        .background(Theme.text.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(selected ? Theme.text.opacity(0.05) : .clear, in: row)
            .contentShape(Rectangle())
        }
        .floatButtonStyle(in: row, highlight: .background)
        .disabled(chat.stopping || chat.answeringQuestion)
        .padding(.horizontal, -4)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    @ViewBuilder private func selectionMark(selected: Bool) -> some View {
        if question.allowsMultiple {
            let box = RoundedRectangle(cornerRadius: 3)
            box.fill(selected ? Theme.accent : .clear)
                .overlay { box.strokeBorder(selected ? Theme.accent : Theme.text.opacity(0.45), lineWidth: 1.5) }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.canvas)
                    }
                }
        } else {
            Circle().strokeBorder(selected ? Theme.accent : Theme.text.opacity(0.45), lineWidth: 1.5)
                .overlay {
                    if selected { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
                }
        }
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
            }
        }
        .floatPillButtonStyle(tint: primary ? tint : nil)
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
                .foregroundStyle(Theme.muted)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .floatButtonStyle()
        .help(title)
        .accessibilityLabel(accessibilityTitle)
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
