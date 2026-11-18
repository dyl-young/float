import Foundation

public struct T3Client: Sendable {
    private struct Upload: Decodable {
        let attachmentId: String
        let relativeUrl: String
    }

    private struct Delivery: Decodable {
        let threadId: String?
        let link: URL?
        let projectId: String?
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
    private struct EnvironmentLinks: Decodable {
        struct Link: Decodable {
            let environmentId: String
            let label: String
            let status: T3Machine.Status
        }

        let environmentId: String
        let links: [Link]
    }
    private struct PendingRequestList: Decodable {
        let requestIds: [String]
    }

    private let transport: MCPTransport
    private let scratchRoot: URL

    public let approvals: ApprovalAccess
    private let approvalRPC: ApprovalRPC

    public init(base: URL? = nil, executable: URL? = nil, desktopApp: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let standardBase = home.appending(path: ".t3")
        let resolvedBase = base ?? standardBase
        scratchRoot = resolvedBase.appending(path: "scratch").resolvingSymlinksInPath()
        let cli = LocalCLI(base: resolvedBase, executable: executable, desktopApp: desktopApp)
        transport = MCPTransport(cli: cli)
        let approvals = ApprovalAccess(cli: cli)
        self.approvals = approvals
        approvalRPC = ApprovalRPC(base: resolvedBase, access: approvals)
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

    public func machines() async throws -> [T3Machine] {
        do {
            let response = try await transport.call(
                "t3_environment_links", [:], result: EnvironmentLinks.self,
                retryExpiredSession: true
            )
            var machines = [
                T3Machine(
                    id: response.environmentId, name: "This Mac", kind: .local,
                    status: .reachable
                ),
            ]
            for link in response.links {
                let count = link.status == .reachable
                    ? try? await projects(environmentID: link.environmentId).count
                    : nil
                machines.append(T3Machine(
                    id: link.environmentId, name: link.label, kind: .linked,
                    status: link.status, projectCount: count
                ))
            }
            return T3MachinePicker.ordered(machines)
        } catch let error as URLError where [
            .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut,
        ].contains(error.code) {
            throw T3Error.serverUnavailable
        }
    }

    public func projects(environmentID: String? = nil) async throws -> [T3Project] {
        do {
            var projects: [T3Project] = []
            var cursor: Int?
            repeat {
                var arguments: [String: any Sendable] = ["limit": 100]
                arguments["cursor"] = cursor
                arguments["environmentId"] = environmentID
                let page = try await transport.call(
                    "t3_project_list", arguments, result: ProjectPage.self,
                    retryExpiredSession: true
                )
                projects.append(contentsOf: page.projects)
                cursor = page.nextCursor
            } while cursor != nil
            return projects.filter(\.isAvailable).filter {
                environmentID != nil
                    || URL(fileURLWithPath: $0.workspaceRoot).resolvingSymlinksInPath() != scratchRoot
            }
        } catch let error as URLError where [
            .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut,
        ].contains(error.code) {
            throw T3Error.serverUnavailable
        }
    }

    public func project(_ id: String, environmentID: String?) async throws -> T3Project {
        var arguments: [String: any Sendable] = ["projectId": id]
        arguments["environmentId"] = environmentID
        return try await transport.call("t3_project_read", arguments, result: T3Project.self, retryExpiredSession: true)
    }

    public static func launchTitle(for text: String, attachmentName: String?) -> String {
        text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(80)) }
            ?? attachmentName ?? "Float chat"
    }

    public func isScratchProject(_ project: T3Project, environmentID: String?) -> Bool {
        if environmentID != nil { return project.title == "No project" }
        return URL(fileURLWithPath: project.workspaceRoot).resolvingSymlinksInPath() == scratchRoot
    }

    public func send(
        _ text: String, images: [ImageAttachment], thread: ThreadReference?, requestId: UUID,
        modelSelection: T3ModelSelection? = nil, projectID: String? = nil,
        environmentID: String? = nil, machineName: String? = nil,
        projectName: String? = nil
    ) async throws -> ThreadReceipt {
        let selection: T3ModelSelection?
        var catalogue: T3ModelCatalogue?
        if thread == nil, modelSelection == nil {
            catalogue = try await modelCatalogue()
            guard let preferred = T3Model.preferred(in: catalogue?.available ?? []) else {
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
                    var arguments: [String: any Sendable] = [
                        "threadId": thread.threadId, "modelSelection": selection.arguments,
                    ]
                    arguments["environmentId"] = thread.environmentID
                    _ = try await transport.call(
                        "t3_thread_configure", arguments, result: Empty.self
                    )
                }
                submitted = true
                if uploads.isEmpty {
                    var arguments: [String: any Sendable] = [
                        "threadId": thread.threadId, "message": text, "mode": "queue",
                        "clientRequestId": requestId.uuidString,
                    ]
                    arguments["environmentId"] = thread.environmentID
                    result = try await transport.call(
                        "t3_thread_send", arguments, result: Delivery.self
                    )
                } else {
                    guard thread.environmentID == nil else {
                        throw T3Error.tool("Attachments cannot be sent to a linked machine yet.")
                    }
                    result = try await transport.call("t3_thread_send_attachments", [
                        "threadId": thread.threadId, "message": text, "attachments": uploads,
                    ], result: Delivery.self)
                }
            } else {
                guard let selection else { throw T3Error.invalidResponse }
                let title = Self.launchTitle(for: text, attachmentName: images.first?.name)
                // Linked machines cap Float at the link's approved access, so they stay Supervised.
                var runtimeMode = "approval-required"
                if environmentID == nil {
                    if catalogue == nil { catalogue = try await modelCatalogue() }
                    runtimeMode = catalogue?.launchRuntimeMode(for: selection.instanceId) ?? runtimeMode
                }
                var arguments: [String: any Sendable] = [
                    "title": title, "message": text, "attachments": uploads,
                    "runtimeMode": runtimeMode, "interactionMode": "default",
                    "clientRequestId": requestId.uuidString,
                    "modelSelection": selection.arguments,
                ]
                if let projectID {
                    arguments["projectId"] = projectID
                } else {
                    arguments["scratch"] = true
                }
                arguments["environmentId"] = environmentID
                submitted = true
                result = try await transport.call(
                    "t3_thread_launch", arguments, result: Delivery.self
                )
            }
            guard let id = result.threadId ?? thread?.threadId else { throw T3Error.invalidResponse }
            let reference = ThreadReference(
                threadId: id, link: result.link ?? thread?.link,
                environmentID: thread?.environmentID ?? environmentID,
                machineName: thread?.machineName ?? machineName,
                projectName: thread?.projectName ?? projectName
            )
            return ThreadReceipt(
                reference: reference, runId: result.runId, status: result.status,
                modelSelection: result.modelSelection ?? selection,
                projectID: thread == nil && projectID != nil ? result.projectId ?? projectID : nil
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
            "threadId": thread.threadId, "view": "activity", "limit": 80, "maxCharsPerItem": 2_000,
            "beforePosition": before ?? 9_007_199_254_740_991, "runLimit": 1,
        ], thread: thread)
    }

    public func pendingApprovals(_ thread: ThreadReference) async throws -> [ApprovalRequest] {
        guard thread.environmentID == nil else { return [] }
        return try await approvalRPC.pending(threadID: thread.threadId)
    }

    public func respondToApproval(_ request: ApprovalRequest, decision: ApprovalDecision,
                                  thread: ThreadReference) async throws {
        guard thread.environmentID == nil, request.allowedDecisions.contains(decision) else {
            throw ApprovalRPCError.commandFailed
        }
        try await approvalRPC.respond(ApprovalCommand(threadId: thread.threadId, requestId: request.id, decision: decision))
    }

    public func pendingQuestion(_ thread: ThreadReference) async throws -> T3PendingQuestionRequest? {
        var listArguments: [String: any Sendable] = [
            "action": "list", "threadId": thread.threadId,
        ]
        listArguments["environmentId"] = thread.environmentID
        let list = try await transport.call(
            "t3_pending_request", listArguments, result: PendingRequestList.self,
            retryExpiredSession: true
        )
        guard let requestId = list.requestIds.first else { return nil }
        var readArguments: [String: any Sendable] = [
            "action": "read", "threadId": thread.threadId, "requestId": requestId,
        ]
        readArguments["environmentId"] = thread.environmentID
        return try await transport.call(
            "t3_pending_request", readArguments, result: T3PendingQuestionRequest.self,
            retryExpiredSession: true
        )
    }

    public func answer(
        _ request: T3PendingQuestionRequest, answers: [String: T3QuestionAnswer],
        thread: ThreadReference
    ) async throws {
        var encoded: [String: any Sendable] = [:]
        for (id, answer) in answers { encoded[id] = answer.argument }
        var arguments: [String: any Sendable] = [
            "action": "respond", "threadId": thread.threadId,
            "requestId": request.requestId, "answers": encoded,
        ]
        arguments["environmentId"] = thread.environmentID
        _ = try await transport.call(
            "t3_pending_request", arguments, result: Empty.self
        )
    }

    /// True when T3 accepted the interrupt or the run was already stopped.
    public func stop(_ thread: ThreadReference, runId: String?) async throws -> Bool {
        var arguments: [String: any Sendable] = ["threadId": thread.threadId]
        arguments["runId"] = runId
        arguments["environmentId"] = thread.environmentID
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
                "threadId": thread.threadId, "view": "activity",
                "itemId": item.itemId, "textOffset": start, "maxCharsPerItem": 20_000,
            ], thread: thread)
            guard let part = page.items.first(where: { $0.itemId == item.itemId }) else { break }
            text += part.text ?? ""
            offset = part.nextTextOffset.flatMap { $0 > start ? $0 : nil }
        }
        return text
    }

    private func readSnapshot(
        _ arguments: [String: any Sendable], thread: ThreadReference
    ) async throws -> ThreadSnapshot {
        do {
            var arguments = arguments
            arguments["environmentId"] = thread.environmentID
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
