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
        let modelSelection: T3ModelSelection?
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

    public func models() async throws -> [T3Model] {
        do {
            return try await transport.call(
                "orchestrator_capabilities", [:], result: T3ModelCatalog.self, retryExpiredSession: true
            ).available
        } catch let error as URLError where [
            .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut,
        ].contains(error.code) {
            throw T3Error.serverUnavailable
        }
    }

    public func send(
        _ text: String, images: [ImageAttachment], thread: ThreadReference?, requestId: UUID,
        modelSelection: T3ModelSelection? = nil
    ) async throws -> ThreadReceipt {
        let selection: T3ModelSelection?
        if thread == nil, modelSelection == nil {
            guard let preferred = T3Model.preferred(in: try await models()) else {
                throw T3Error.tool("Enable Codex or Claude Code in T3 Settings → Providers to send a prompt.")
            }
            selection = preferred.selection
        } else {
            selection = modelSelection
        }
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
            if let thread {
                if let selection {
                    _ = try await transport.call("t3_thread_configure", [
                        "threadId": thread.threadId, "modelSelection": selection.arguments,
                    ], result: Empty.self)
                }
                submitted = true
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
                guard let selection else { throw T3Error.invalidResponse }
                let title = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(80)) }
                    ?? images.first?.name ?? "Float chat"
                submitted = true
                result = try await transport.call("t3_thread_launch", [
                    "title": title, "scratch": true, "message": text, "attachments": uploads,
                    "runtimeMode": "approval-required", "interactionMode": "default",
                    "clientRequestId": requestId.uuidString,
                    "modelSelection": selection.arguments,
                ], result: Delivery.self)
            }
            guard let id = result.threadId ?? thread?.threadId else { throw T3Error.invalidResponse }
            let reference = ThreadReference(threadId: id, link: result.link ?? thread?.link)
            return ThreadReceipt(
                reference: reference, runId: result.runId, status: result.status,
                modelSelection: result.modelSelection ?? selection
            )
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
        return try await readSnapshot(args)
    }

    public func readRemainder(
        _ thread: ThreadReference, item: ThreadSnapshot.Item
    ) async throws -> String {
        var text = item.text ?? ""
        var offset = item.nextTextOffset
        while let start = offset {
            let page = try await readSnapshot([
                "threadId": thread.threadId, "view": "messages",
                "itemId": item.itemId, "textOffset": start, "maxCharsPerItem": 20_000,
            ])
            guard let part = page.items.first(where: { $0.itemId == item.itemId }) else { break }
            text += part.text ?? ""
            offset = part.nextTextOffset.flatMap { $0 > start ? $0 : nil }
        }
        return text
    }

    private func readSnapshot(_ arguments: [String: any Sendable]) async throws -> ThreadSnapshot {
        do {
            return try await transport.call(
                "t3_thread_read", arguments, result: ThreadSnapshot.self, retryExpiredSession: true
            )
        } catch let error as URLError where [
            .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut,
        ].contains(error.code) {
            throw T3Error.serverUnavailable
        }
    }
}
