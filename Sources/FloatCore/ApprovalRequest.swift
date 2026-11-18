import Foundation

public enum ApprovalDecision: String, Codable, Sendable {
    case allow = "accept"
    case deny = "decline"
}

public struct ApprovalRequest: Equatable, Identifiable, Sendable {
    public let id: String
    public let action: String
    public let command: String?
    public let detail: String?
    public let reason: String?
    public let paths: [String]
    public let allowedDecisions: Set<ApprovalDecision>

    public var summary: String { command ?? detail ?? paths.first ?? action }
}

struct ApprovalCommand: Encodable, Sendable {
    let type = "runtime-request.respond"
    let commandId = UUID().uuidString
    let threadId: String
    let requestId: String
    let decision: ApprovalDecision
}

struct ApprovalProjection: Decodable, Sendable {
    struct RuntimeRequest: Decodable, Sendable {
        struct Capability: Decodable, Sendable { let type: String }
        let id: String
        let kind: String
        let status: String
        let responseCapability: Capability
        let createdAt: String
    }

    struct ToolKey: Hashable, Sendable {
        let driver: String
        let nativeID: String
        let turnID: String
    }

    struct TurnItem: Decodable, Sendable {
        struct Option: Decodable, Sendable { let decision: String }
        struct Reference: Decodable {
            let driver: String
            let nativeId: String?
        }
        struct File: Decodable { let path: String }
        struct ToolInput: Decodable {
            let path: String?
            let filePath: String?
            let file_path: String?
        }

        let toolKey: ToolKey?
        let type: String
        let requestId: String?
        let requestKind: String?
        let prompt: String?
        let reason: String?
        let appName: String?
        let options: [Option]?
        let command: String?
        let paths: [String]?

        enum CodingKeys: String, CodingKey {
            case type, requestId, requestKind, prompt, reason, appName, options, command, paths
            case nativeItemRef, providerTurnId, input, fileName, changes
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(String.self, forKey: .type)
            requestId = try values.decodeIfPresent(String.self, forKey: .requestId)
            if let turnID = try values.decodeIfPresent(String.self, forKey: .providerTurnId),
               let reference = try values.decodeIfPresent(Reference.self, forKey: .nativeItemRef),
               let nativeID = reference.nativeId {
                toolKey = ToolKey(driver: reference.driver, nativeID: nativeID, turnID: turnID)
            } else {
                toolKey = nil
            }
            // Other item types can carry their own prompt, paths, or options.
            guard type == "approval_request" else {
                requestKind = nil
                prompt = nil
                reason = nil
                appName = nil
                options = nil
                command = type == "command_execution" ? try values.decodeIfPresent(String.self, forKey: .input) : nil
                if type == "file_change" {
                    let changes = try values.decodeIfPresent([File].self, forKey: .changes) ?? []
                    let name = try values.decodeIfPresent(String.self, forKey: .fileName)
                    paths = changes.isEmpty ? name.map { [$0] } : changes.map(\.path)
                } else if type == "dynamic_tool", let input = try? values.decode(ToolInput.self, forKey: .input) {
                    paths = (input.filePath ?? input.file_path ?? input.path).map { [$0] }
                } else {
                    paths = nil
                }
                return
            }
            requestKind = try values.decodeIfPresent(String.self, forKey: .requestKind)
            prompt = try values.decodeIfPresent(String.self, forKey: .prompt)
            reason = try values.decodeIfPresent(String.self, forKey: .reason)
            appName = try values.decodeIfPresent(String.self, forKey: .appName)
            options = try values.decodeIfPresent([Option].self, forKey: .options)
            // T3's V2 wire contract does not require separate commands or paths.
            command = try? values.decode(String.self, forKey: .command)
            paths = try? values.decode([String].self, forKey: .paths)
        }
    }

    let runtimeRequests: [RuntimeRequest]
    let turnItems: [TurnItem]

    var pendingApprovals: [ApprovalRequest] {
        let items = turnItems.reduce(into: [String: TurnItem]()) { result, item in
            if item.type == "approval_request", let id = item.requestId { result[id] = item }
        }
        // ACP approval prompts can be tool titles. The request and tool share
        // a native call ID within the same provider turn.
        let toolDetails = turnItems.reduce(into: [ToolKey: TurnItem]()) { result, item in
            if item.type != "approval_request", let key = item.toolKey,
               item.command != nil || item.paths != nil {
                result[key] = item
            }
        }
        return runtimeRequests.enumerated()
            .filter { $0.element.status == "pending" && items[$0.element.id] != nil }
            .sorted {
                let lhs = t3Date($0.element.createdAt) ?? .distantPast
                let rhs = t3Date($1.element.createdAt) ?? .distantPast
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }
            .compactMap { entry in
                let request = entry.element
                guard let item = items[request.id] else { return nil }
                return Self.present(request, item: item, tool: item.toolKey.flatMap { toolDetails[$0] })
            }
    }

    private static func present(_ request: RuntimeRequest, item: TurnItem, tool: TurnItem?) -> ApprovalRequest {
        let kind = item.requestKind ?? request.kind
        let prompt = nonEmpty(item.prompt)
        let command = nonEmpty(item.command) ?? nonEmpty(tool?.command) ?? (kind == "command" ? prompt : nil)
        let action: String
        switch kind {
        case _ where command != nil: action = "Wants to run"
        case "command": action = "Wants to run a command"
        case "file-read": action = "Wants to read files"
        case "file-change": action = "Wants to change files"
        case "mcp-elicitation": action = "Needs input for \(nonEmpty(item.appName) ?? "a tool")"
        default: action = "Needs permission to continue"
        }
        let detail = prompt == command || (tool?.command != nil && prompt == "Ran command") ? nil : prompt
        let reason = nonEmpty(item.reason)
        let options = item.options ?? []
        let decisions = options.isEmpty ? Set([ApprovalDecision.allow, .deny])
            : Set(options.compactMap { ApprovalDecision(rawValue: $0.decision) })
        return ApprovalRequest(
            id: request.id, action: action, command: command, detail: detail,
            reason: reason == command || reason == detail ? nil : reason,
            paths: item.paths ?? tool?.paths ?? [],
            allowedDecisions: request.responseCapability.type == "live" ? decisions : []
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}


extension ThreadSnapshot.Item {
    public var isPendingApproval: Bool {
        type == "approval_request" && ["pending", "running", "waiting"].contains(status)
    }
}
