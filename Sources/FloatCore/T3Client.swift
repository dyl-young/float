import Foundation

public struct T3Client: Sendable {
    private struct Upload: Decodable {
        let attachmentId: String
        let relativeUrl: String
    }

    private struct Delivery: Decodable {
        let threadId: String?
        let link: URL?
        let runId: String
        let status: RunStatus
    }

    private struct Empty: Decodable {}

    private let transport: MCPTransport

    public init(base: URL? = nil, executable: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let standardBase = home.appending(path: ".t3")
        transport = MCPTransport(cli: LocalCLI(
            base: base ?? standardBase,
            executable: executable ?? standardBase.appending(path: "bin/t3")
        ))
    }

    public func close() async { await transport.close() }

    public func send(
        _ text: String, images: [ImageAttachment], thread: ThreadReference?, requestId: UUID
    ) async throws -> ThreadReceipt {
        var uploads: [[String: any Sendable]] = []
        var submitted = false
        do {
            for image in images {
                let info: [String: any Sendable] = [
                    "type": "image", "name": image.name,
                    "mimeType": image.mimeType, "sizeBytes": image.data.count,
                ]
                let pending = try await transport.call(
                    "t3_attachment_prepare_upload", ["upload": info], result: Upload.self
                )
                var attachment = info
                attachment["id"] = pending.attachmentId
                uploads.append(attachment)
                try await transport.upload(image.data, mimeType: image.mimeType, relativePath: pending.relativeUrl)
            }

            let result: Delivery
            submitted = true
            if let thread {
                if uploads.isEmpty {
                    result = try await transport.call("t3_thread_send", [
                        "threadId": thread.threadId, "message": text, "mode": "queue",
                        "clientRequestId": requestId.uuidString,
                    ], result: Delivery.self)
                } else {
                    result = try await transport.call("t3_thread_send_attachments", [
                        "threadId": thread.threadId, "message": text, "attachments": uploads,
                    ], result: Delivery.self)
                }
            } else {
                let title = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(80)) }
                    ?? images.first?.name ?? "Float chat"
                result = try await transport.call("t3_thread_launch", [
                    "title": title, "scratch": true, "message": text, "attachments": uploads,
                    "runtimeMode": "approval-required", "interactionMode": "default",
                    "clientRequestId": requestId.uuidString,
                    "modelSelection": ["instanceId": "claudeAgent", "model": "claude-opus-5-5"],
                ], result: Delivery.self)
            }
            guard let id = result.threadId ?? thread?.threadId else { throw T3Error.invalidResponse }
            let reference = ThreadReference(threadId: id, link: result.link ?? thread?.link)
            return ThreadReceipt(reference: reference, runId: result.runId, status: result.status)
        } catch {
            if submitted {
                switch error {
                case T3Error.http(let status) where (400..<500).contains(status): break
                case T3Error.tool, T3Error.serverUnavailable, T3Error.authorization,
                    T3Error.cliUnavailable, T3Error.localAddressRequired: break
                default: throw T3Error.uncertainDelivery
                }
            }
            for upload in uploads {
                if let id = upload["id"] as? String {
                    _ = try? await transport.call("t3_attachment_discard", ["attachmentId": id], result: Empty.self)
                }
            }
            if let urlError = error as? URLError,
                [.cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code) {
                throw T3Error.serverUnavailable
            }
            throw error
        }
    }

    public func read(_ thread: ThreadReference, before: Int? = nil) async throws -> ThreadSnapshot {
        var args: [String: any Sendable] = [
            "threadId": thread.threadId, "view": "messages", "limit": 40, "maxCharsPerItem": 20_000,
        ]
        args["beforePosition"] = before
        do {
            return try await transport.call("t3_thread_read", args, result: ThreadSnapshot.self)
        } catch let error as URLError where [.cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet].contains(error.code) {
            throw T3Error.serverUnavailable
        }
    }

    public func readRemainder(
        _ thread: ThreadReference, item: ThreadSnapshot.Item
    ) async throws -> String {
        var text = item.text ?? ""
        var offset = item.nextTextOffset
        while let start = offset {
            let page = try await transport.call("t3_thread_read", [
                "threadId": thread.threadId, "view": "messages",
                "itemId": item.itemId, "textOffset": start, "maxCharsPerItem": 20_000,
            ], result: ThreadSnapshot.self)
            guard let part = page.items.first(where: { $0.itemId == item.itemId }) else { break }
            text += part.text ?? ""
            offset = part.nextTextOffset.flatMap { $0 > start ? $0 : nil }
        }
        return text
    }
}
