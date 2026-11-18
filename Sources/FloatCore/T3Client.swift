import Foundation

public struct T3Client: Sendable {
    private struct Upload: Decodable {
        let attachmentId: String
        let relativeUrl: String
    }

    private struct Delivery: Decodable {
        let threadId: String?
        let messageId: String?
        let delivery: String?
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
    private struct ThreadListPage: Decodable {
        let threads: [T3ThreadListItem]
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
    private let followUpSettings: URL
    private let rpc: LocalRPC
    private let cli: LocalCLI

    public let approvals: ApprovalAccess
    private let approvalRPC: ApprovalRPC
    private let inventoryRPC: ComposerInventoryRPC
    private let faviconRPC: ProjectFaviconRPC

    public init(base: URL? = nil, executable: URL? = nil, desktopApp: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let standardBase = home.appending(path: ".t3")
        let resolvedBase = base ?? standardBase
        scratchRoot = resolvedBase.appending(path: "scratch").resolvingSymlinksInPath()
        followUpSettings = resolvedBase.appending(path: "userdata/client-settings.json")
        let cli = LocalCLI(base: resolvedBase, executable: executable, desktopApp: desktopApp)
        self.cli = cli
        transport = MCPTransport(cli: cli)
        let approvals = ApprovalAccess(cli: cli)
        self.approvals = approvals
        let rpc = LocalRPC(base: resolvedBase)
        self.rpc = rpc
        approvalRPC = ApprovalRPC(rpc: rpc, access: approvals)
        inventoryRPC = ComposerInventoryRPC(rpc: rpc, cli: cli)
        faviconRPC = ProjectFaviconRPC(rpc: rpc, cli: cli)
    }

    public func close() async {
        await transport.close()
        await faviconRPC.close()
    }

    public func projectFavicon(_ project: T3Project, environmentID: String?) async throws -> Data? {
        // MCP project tools forward metadata to linked machines. The peer connection
        // does not expose assets.createUrl or a remote RPC credential to Float.
        guard environmentID == nil else { return nil }
        return try await faviconRPC.data(cwd: project.workspaceRoot, path: project.faviconPath)
    }

    public func modelCatalogue(search: String? = nil, environmentID: String? = nil) async throws -> T3ModelCatalogue {
        do {
            var arguments: [String: any Sendable] = [:]
            arguments["search"] = search
            arguments["environmentId"] = environmentID
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

    public func followUpMode() -> FollowUpMode {
        FollowUpMode.setting(in: try? Data(contentsOf: followUpSettings))
    }

    public func followUpProjection(_ thread: ThreadReference) async throws -> T3FollowUpProjection {
        struct Input: Encodable { let threadId: String }
        let credential = try await cli.issueFollowUpReader()
        do {
            let result: T3FollowUpProjection = try await rpc.call(
                "orchestration.getThreadProjection", Input(threadId: thread.threadId), credential: credential
            )
            await cli.revoke(credential)
            return result
        } catch {
            await cli.revoke(credential)
            throw error
        }
    }

    public func queuedFollowUps(_ thread: ThreadReference) async throws -> [T3QueuedFollowUp] {
        struct Page: Decodable, Sendable {
            let items: [T3QueuedFollowUp]
            let nextCursor: Int?
        }
        var arguments: [String: any Sendable] = ["threadId": thread.threadId, "action": "list", "limit": 100]
        arguments["environmentId"] = thread.environmentID
        var items: [T3QueuedFollowUp] = []
        var cursor: Int?
        repeat {
            arguments["cursor"] = cursor
            let page = try await transport.call("t3_queue", arguments, result: Page.self, retryExpiredSession: true)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil && !Task.isCancelled
        return items
    }

    public func cancelQueuedFollowUp(_ runID: String, in thread: ThreadReference) async throws {
        var arguments: [String: any Sendable] = [
            "threadId": thread.threadId, "action": "cancel", "queuedRunId": runID,
        ]
        arguments["environmentId"] = thread.environmentID
        _ = try await transport.call("t3_queue", arguments, result: Empty.self)
    }

    public func composerInventory(instanceID: String, cwd: String?) async throws -> T3ComposerInventory {
        try await inventoryRPC.inventory(instanceID: instanceID, cwd: cwd)
    }

    public func models() async throws -> [T3Model] {
        try await modelCatalogue().available
    }

    public func machines() async throws -> [T3Machine] {
        do {
            let response = try await environmentLinks()
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

    private func environmentLinks() async throws -> EnvironmentLinks {
        try await transport.call(
            "t3_environment_links", [:], result: EnvironmentLinks.self, retryExpiredSession: true
        )
    }

    public func chatSwitcherCatalog() async throws -> ChatSwitcherCatalog {
        let links = try? await environmentLinks()
        return try await withThrowingTaskGroup(of: [ChatSwitcherEntry]?.self) { group in
            group.addTask {
                try await threadList(environmentID: nil, machineName: nil)
            }
            for link in links?.links ?? [] where link.status == .reachable {
                group.addTask {
                    try? await threadList(environmentID: link.environmentId, machineName: link.label)
                }
            }
            var entries: [ChatSwitcherEntry] = []
            var unavailable = links == nil
            for try await result in group {
                if let result { entries.append(contentsOf: result) }
                else { unavailable = true }
            }
            return ChatSwitcherCatalog(groups: ChatSwitcherGroup.group(entries), hasUnavailableMachines: unavailable)
        }
    }

    private func threadList(environmentID: String?, machineName: String?) async throws -> [ChatSwitcherEntry] {
        async let projectList = try? projects(environmentID: environmentID)
        var threads: [T3ThreadListItem] = []
        var cursor: Int?
        repeat {
            var arguments: [String: any Sendable] = [
                "allProjects": true, "includeSubagents": false, "settled": false, "limit": 100,
            ]
            arguments["environmentId"] = environmentID
            arguments["cursor"] = cursor
            let page = try await transport.call(
                "t3_thread_list", arguments, result: ThreadListPage.self, retryExpiredSession: true
            )
            threads.append(contentsOf: page.threads)
            cursor = page.nextCursor
        } while cursor != nil

        let projects = Dictionary((await projectList ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = threads.map { thread in
            let project = projects[thread.projectId].flatMap {
                isScratchProject($0, environmentID: environmentID) ? nil : $0
            }
            let reference = ThreadReference(
                threadId: thread.threadId, link: thread.linkURL, environmentID: environmentID,
                machineName: machineName, projectName: project?.title
            )
            return ChatSwitcherEntry(thread: thread, reference: reference, project: project)
        }
        return await withTaskGroup(of: ChatSwitcherEntry.self) { group in
            var result = entries.filter { $0.thread.status != .running }
            for entry in entries where entry.thread.status == .running {
                group.addTask {
                    let page = try? await read(entry.reference, messagesLimit: 1)
                    let run = page?.recentRuns?.first { $0.runId == entry.thread.latestRunId && $0.status.isInProgress }
                    return ChatSwitcherEntry(
                        thread: entry.thread, reference: entry.reference, project: entry.project,
                        runStartedAt: (run?.startedAt ?? run?.requestedAt).flatMap(t3Date)
                    )
                }
            }
            for await entry in group { result.append(entry) }
            return result
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
        projectName: String? = nil, followUp: FollowUpMode? = nil
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
        if followUp == .queue, !images.isEmpty {
            throw T3Error.tool("Queueing images from Float is unavailable. Your draft and images are still here.")
        }
        if thread?.environmentID != nil, !images.isEmpty {
            throw T3Error.tool("Attachments cannot be sent to a linked machine yet.")
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
                        "threadId": thread.threadId, "message": text, "mode": (followUp ?? .queue).rawValue,
                        "clientRequestId": requestId.uuidString,
                    ]
                    arguments["environmentId"] = thread.environmentID
                    do {
                        result = try await transport.call("t3_thread_send", arguments, result: Delivery.self)
                    } catch T3Error.tool(let message) where followUp == .steer && Self.steerWasRejected(message) {
                        // T3 rejected before accepting the message. Keep the request ID
                        // when the active turn stopped, became unavailable or compacted.
                        arguments["mode"] = FollowUpMode.queue.rawValue
                        result = try await transport.call("t3_thread_send", arguments, result: Delivery.self)
                    }
                } else {
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
                projectID: thread == nil && projectID != nil ? result.projectId ?? projectID : nil,
                messageID: result.messageId, delivery: result.delivery
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

    static func steerWasRejected(_ message: String) -> Bool {
        let message = message.lowercased()
        return message.contains("no running turn that can be steered")
            || message.contains("cannot be steered")
            || message.contains("no active provider session for steering")
            || message.contains("wait for context compaction to finish before steering")
            || message.contains("cannot steer active turns directly")
            || message.contains("does not support active steering")
    }

    public func read(_ thread: ThreadReference, before: Int? = nil, messagesLimit: Int? = nil) async throws -> ThreadSnapshot {
        // T3 reads forward for external clients unless given an upper bound.
        // Use the largest JSON-safe integer to request the newest page.
        try await readSnapshot([
            "threadId": thread.threadId, "view": messagesLimit == nil ? "activity" : "messages",
            "limit": messagesLimit ?? 80, "maxCharsPerItem": 2_000,
            "beforePosition": before ?? 9_007_199_254_740_991, "runLimit": 1,
        ], thread: thread)
    }

    public func resumeHistory(
        _ thread: ThreadReference
    ) async throws -> (items: [ThreadSnapshot.Item], hasOlder: Bool) {
        let limit = 10
        var items: [ThreadSnapshot.Item] = []
        var cursor: Int?
        repeat {
            let page = try await read(thread, before: cursor, messagesLimit: limit + 1 - items.count)
            items.append(contentsOf: page.items.filter(\.isMessage).sorted { $0.position > $1.position })
            let earlier = page.earlierPosition
            cursor = earlier == cursor ? nil : earlier
        } while items.count <= limit && cursor != nil
        return (Array(items.prefix(limit)), items.count > limit)
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

    public func pendingQuestion(
        _ thread: ThreadReference, excluding answeredIDs: Set<String> = []
    ) async throws -> T3PendingQuestionRequest? {
        var listArguments: [String: any Sendable] = [
            "action": "list", "threadId": thread.threadId,
        ]
        listArguments["environmentId"] = thread.environmentID
        let list = try await transport.call(
            "t3_pending_request", listArguments, result: PendingRequestList.self,
            retryExpiredSession: true
        )
        guard let requestId = list.requestIds.first(where: { !answeredIDs.contains($0) }) else { return nil }
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
