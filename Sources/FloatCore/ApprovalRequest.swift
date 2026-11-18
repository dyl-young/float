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

    struct TurnItem: Decodable, Sendable {
        struct Option: Decodable, Sendable { let decision: String }
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
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(String.self, forKey: .type)
            requestId = try values.decodeIfPresent(String.self, forKey: .requestId)
            // Other item types can carry their own prompt, paths, or options.
            guard type == "approval_request" else {
                requestKind = nil
                prompt = nil
                reason = nil
                appName = nil
                options = nil
                command = nil
                paths = nil
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
                return Self.present(request, item: item)
            }
    }

    private static func present(_ request: RuntimeRequest, item: TurnItem) -> ApprovalRequest {
        let kind = item.requestKind ?? request.kind
        let prompt = nonEmpty(item.prompt)
        let action: String
        switch kind {
        case "command": action = "Wants to run"
        case "file-read": action = "Wants to read files"
        case "file-change": action = "Wants to change files"
        case "mcp-elicitation": action = "Needs input for \(nonEmpty(item.appName) ?? "a tool")"
        default: action = "Needs permission to continue"
        }
        let command = nonEmpty(item.command) ?? (kind == "command" ? prompt : nil)
        let detail = prompt == command ? nil : prompt
        let reason = nonEmpty(item.reason)
        let options = item.options ?? []
        let decisions = options.isEmpty ? Set([ApprovalDecision.allow, .deny])
            : Set(options.compactMap { ApprovalDecision(rawValue: $0.decision) })
        return ApprovalRequest(
            id: request.id, action: action, command: command, detail: detail,
            reason: reason == command || reason == detail ? nil : reason,
            paths: item.paths ?? [],
            allowedDecisions: request.responseCapability.type == "live" ? decisions : []
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
