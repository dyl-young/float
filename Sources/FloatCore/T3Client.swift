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
    private struct Interruption: Decodable {
        let status: String
    }
    private struct ProjectPage: Decodable {
        let projects: [T3Project]
        let nextCursor: Int?
    }

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

    public func modelCatalogue(search: String? = nil) async throws -> T3ModelCatalogue {
        do {
            var arguments: [String: any Sendable] = [:]
            arguments["search"] = search
            return try await transport.call(
                "orchestrator_capabilities", arguments,
                result: T3ModelCatalog.self, retryExpiredSession: true
            ).catalogue
        } catch let error as URLError where [
            .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut,
        ].contains(error.code) {
            throw T3Error.serverUnavailable
        }
    }

    public func models() async throws -> [T3Model] {
        try await modelCatalogue().available
    }

    public func projects() async throws -> [T3Project] {
        do {
            var projects: [T3Project] = []
            var cursor: Int?
            repeat {
                var arguments: [String: any Sendable] = ["limit": 100]
                arguments["cursor"] = cursor
                let page = try await transport.call(
                    "t3_project_list", arguments, result: ProjectPage.self,
                    retryExpiredSession: true
                )
                projects.append(contentsOf: page.projects)
                cursor = page.nextCursor
            } while cursor != nil
            return projects.filter(\.isAvailable)
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
                throw T3Error.tool("Enable a supported provider in T3 Settings → Providers to send a prompt.")
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
        // T3 reads forward for external clients unless given an upper bound.
        // Use the largest JSON-safe integer to request the newest page.
        try await readSnapshot([
            "threadId": thread.threadId, "view": "messages", "limit": 40, "maxCharsPerItem": 20_000,
            "beforePosition": before ?? 9_007_199_254_740_991, "runLimit": 1,
        ])
    }

    /// True when T3 accepted the interrupt or the run was already stopped.
    public func stop(_ thread: ThreadReference, runId: String?) async throws -> Bool {
        var arguments = ["threadId": thread.threadId]
        arguments["runId"] = runId
        let result = try await transport.call(
            "t3_thread_interrupt", arguments, result: Interruption.self
        )
        return result.status == "interrupt_requested" || RunStatus(result.status) == .stopped
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
