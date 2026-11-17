import AppKit
import FloatCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ChatMessage: Identifiable {
    var id: String
    let runId: String?
    let position: Int
    let isUser: Bool
    var text: String
    let date: Date?
    let previews: [Data]
}

@MainActor
final class ChatState: ObservableObject {
    @Published var draft: String { didSet { defaults.set(draft, forKey: "draft") } }
    @Published private(set) var images: [ImageAttachment] = []
    @Published private(set) var reference: ThreadReference?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var title: String?
    @Published private(set) var status: RunStatus = .idle
    @Published private(set) var submitting = false
    @Published private(set) var loading = false
    @Published private(set) var hasOlderMessages = false
    @Published private(set) var loadingOlder = false
    @Published private(set) var notice: String?
    @Published private(set) var needsT3 = false
    @Published private(set) var focusRequest = 0

    private let defaults: UserDefaults
    private let client: T3Client
    private var watcher: Task<Void, Never>?
    private var previews: [String: [Data]] = [:]
    private var earliest: Int?
    private var receivedFirstPage = false
    private var generation = 0
    private var visible = false
    private var completedText: [String: (timestamp: String, text: String)] = [:]
    private var pendingMessage: ChatMessage?

    init(client: T3Client, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.client = client
        draft = defaults.string(forKey: "draft") ?? ""
        if let data = defaults.data(forKey: "thread"),
            let stored = try? JSONDecoder().decode(ThreadReference.self, from: data) {
            reference = stored
            if let encoded = defaults.data(forKey: "previews") {
                previews = (try? PropertyListDecoder().decode([String: [Data]].self, from: encoded)) ?? [:]
            }
        }
    }

    var hasConversation: Bool { reference != nil || submitting }
    var canSend: Bool {
        !submitting && !loading && status != .running && status != .waiting &&
            (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    func revealed() {
        visible = true
        focusRequest += 1
        if let reference { refresh(reference, force: watcher == nil) }
    }

    func hidden() { visible = false }

    func newChat() {
        guard !submitting else { return }
        generation += 1
        watcher?.cancel()
        watcher = nil
        draft = ""
        images = []
        reference = nil
        messages = []
        title = nil
        status = .idle
        notice = nil
        needsT3 = false
        loading = false
        hasOlderMessages = false
        loadingOlder = false
        pendingMessage = nil
        earliest = nil
        receivedFirstPage = false
        completedText = [:]
        previews = [:]
        persist()
        focusRequest += 1
    }

    func openThread() {
        guard let url = reference?.desktopURL else { return }
        if !NSWorkspace.shared.open(url) {
            needsT3 = true
            notice = "Float couldn’t open the thread in T3 Code."
        }
    }

    func launchT3() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.t3tools.t3code") else {
            notice = "T3 Code isn’t installed. Download it from t3.codes."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                guard let message else { return }
                self.notice = message
                self.needsT3 = true
            }
        }
        needsT3 = false
        notice = nil
    }

    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf16.count <= 120_000 else {
            notice = "T3 accepts up to 120,000 characters per message."
            return
        }
        let attachments = images
        let request = UUID()
        let target = reference
        notice = nil
        needsT3 = false
        submitting = true
        watcher?.cancel()
        watcher = nil

        Task {
            do {
                let receipt = try await client.send(text, images: attachments, thread: target, requestId: request)
                reference = receipt.reference
                if !attachments.isEmpty {
                    previews[receipt.runId] = attachments.compactMap { Self.thumbnail($0.data) }
                }
                let message = ChatMessage(
                    id: request.uuidString, runId: receipt.runId, position: .max, isUser: true, text: text, date: .now,
                    previews: previews[receipt.runId] ?? []
                )
                pendingMessage = message
                messages.append(message)
                status = receipt.status
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
                let sent = Set(attachments.map(\.id))
                images.removeAll { sent.contains($0.id) }
                persist()
                refresh(receipt.reference, force: true)
            } catch {
                showError(error)
                if status == .running, let target { refresh(target, force: true) }
            }
            submitting = false
            focusRequest += 1
        }
    }

    func loadOlder() {
        guard let reference, let before = earliest, !loadingOlder else { return }
        let version = generation
        loadingOlder = true
        Task {
            defer { if generation == version { loadingOlder = false } }
            do {
                let page = try await client.read(reference, before: before)
                try await expandLongMessages(page, reference: reference, generation: version)
                guard generation == version else { return }
                earliest = page.earlierPosition
                hasOlderMessages = earliest != nil
                merge(page)
            } catch {
                guard generation == version else { return }
                showError(error)
            }
        }
    }

    func addImageFiles(_ urls: [URL]) {
        for url in urls {
            guard images.count < ImageAttachment.maxCount else {
                notice = "Attach up to eight images per message."
                break
            }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= ImageAttachment.maxBytes else {
                    notice = "Images must be 10 MB or smaller."
                    continue
                }
                addImage(try Data(contentsOf: url), name: url.lastPathComponent)
            } catch {
                notice = "Float couldn’t open \(url.lastPathComponent)."
            }
        }
    }

    func pasteImages(_ pasteboard: NSPasteboard) -> Bool {
        if let files = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !files.isEmpty {
            let imageFiles = files.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
            if !imageFiles.isEmpty {
                addImageFiles(imageFiles)
                return true
            }
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff, .init("public.jpeg"),
            .init("com.compuserve.gif"), .init("org.webmproject.webp")] {
            if let data = pasteboard.data(forType: type) {
                addImage(data, name: "Pasted image")
                return true
            }
        }
        return false
    }

    func removeImage(_ id: UUID) { images.removeAll { $0.id == id } }

    func close() async { await client.close() }

    private func refresh(_ reference: ThreadReference, force: Bool) {
        guard force else { return }
        watcher?.cancel()
        if messages.isEmpty { loading = true }
        let version = generation
        watcher = Task {
            defer {
                if generation == version && !Task.isCancelled {
                    watcher = nil
                    loading = false
                }
            }
            repeat {
                do {
                    let page = try await client.read(reference)
                    try Task.checkCancellation()
                    try await expandLongMessages(page, reference: reference, generation: version)
                    guard generation == version, !Task.isCancelled else { return }
                    merge(page)
                    if !receivedFirstPage {
                        receivedFirstPage = true
                        earliest = page.earlierPosition
                        hasOlderMessages = earliest != nil
                    }
                    status = page.thread.pendingRequestCount > 0 ? .waiting : page.thread.status
                    title = page.thread.title
                    loading = false
                    if needsT3 {
                        notice = nil
                        needsT3 = false
                    }
                    if status != .running && status != .waiting { return }
                } catch {
                    guard generation == version && !Task.isCancelled else { return }
                    showError(error)
                    loading = false
                    if status != .running && status != .waiting { return }
                }
                try? await Task.sleep(for: visible ? .milliseconds(850) : .seconds(3))
            } while !Task.isCancelled
        }
    }

    private func merge(_ snapshot: ThreadSnapshot) {
        var merged = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for item in snapshot.items where item.type == "user_message" || item.type == "assistant_message" {
            let isUser = item.type == "user_message"
            let text = completedText[item.id]?.text ?? item.text ?? ""
            let attachments = isUser ? item.runId.flatMap { previews[$0] } ?? [] : []
            guard !text.isEmpty || !attachments.isEmpty else { continue }
            if isUser, let pending = pendingMessage, pending.runId == item.runId {
                merged.removeValue(forKey: pending.id)
                pendingMessage = nil
            }
            merged[item.id] = ChatMessage(
                id: item.id, runId: item.runId, position: item.position, isUser: isUser, text: text,
                date: item.date, previews: attachments
            )
        }
        messages = merged.values.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id < $1.id
        }
    }

    private func expandLongMessages(
        _ snapshot: ThreadSnapshot, reference: ThreadReference, generation version: Int
    ) async throws {
        for item in snapshot.items where item.textTruncated && item.status == "completed" &&
            completedText[item.id]?.timestamp != item.updatedAt {
            let text = try await client.readRemainder(reference, item: item)
            guard generation == version, !Task.isCancelled else { return }
            completedText[item.id] = (item.updatedAt, text)
        }
    }

    private func showError(_ error: Error) {
        if case T3Error.serverUnavailable = error {
            needsT3 = true
            notice = "The local T3 server is unavailable."
        } else {
            let text = error.localizedDescription
            notice = text.contains("Provider instance \"claudeAgent\" is disabled")
                ? "Claude Code is disabled in T3. Enable it in T3 Settings → Providers and sign in if needed."
                : text
        }
    }

    private func persist() {
        defaults.set(reference.flatMap { try? JSONEncoder().encode($0) }, forKey: "thread")
        defaults.set(previews.isEmpty ? nil : try? PropertyListEncoder().encode(previews), forKey: "previews")
    }

    private func addImage(_ data: Data, name: String) {
        guard images.count < ImageAttachment.maxCount else {
            notice = "Attach up to eight images per message."
            return
        }
        guard data.count <= ImageAttachment.maxBytes else {
            notice = "Images must be 10 MB or smaller."
            return
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String)
        else {
            notice = "Float couldn’t read that image."
            return
        }
        let payload: (data: Data, type: UTType)
        if [UTType.png, .jpeg, .gif, .webP].contains(type) {
            payload = (data, type)
        } else if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceThumbnailMaxPixelSize: 4_096, kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary), let png = Self.encode(image, as: .png) {
            payload = (png, .png)
        } else {
            notice = "Float couldn’t convert that image."
            return
        }
        guard payload.data.count <= ImageAttachment.maxBytes else {
            notice = "The converted image exceeds T3’s 10 MB limit."
            return
        }
        let ext = payload.type.preferredFilenameExtension ?? "png"
        let finalName = URL(fileURLWithPath: name).pathExtension.isEmpty
            ? "\(name).\(ext)" : URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent + ".\(ext)"
        images.append(ImageAttachment(
            name: String(finalName.prefix(255)), mimeType: payload.type.preferredMIMEType ?? "image/png",
            data: payload.data
        ))
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
        else { return nil }
        return encode(image, as: .jpeg)
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let output = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        return CGImageDestinationFinalize(writer) ? output as Data : nil
    }
}
