import Foundation

public enum T3Error: LocalizedError, Sendable {
    case serverUnavailable
    case localAddressRequired
    case cliUnavailable
    case authorization
    case http(Int)
    case invalidResponse
    case tool(String)
    case uncertainDelivery

    public var errorDescription: String? {
        switch self {
        case .serverUnavailable: "Float can’t reach the local T3 server. Launch T3 Code and try again."
        case .localAddressRequired: "Float needs a loopback address for the local T3 server."
        case .cliUnavailable: "Float couldn’t find the T3 CLI at ~/.t3/bin/t3."
        case .authorization: "T3 couldn’t authorize Float. Check that your local T3 CLI and app are up to date."
        case .http(let status): "The local T3 server returned HTTP \(status)."
        case .invalidResponse: "The local T3 server returned an unexpected response."
        case .tool(let message): message
        case .uncertainDelivery: "T3 may have received this message. Check the thread before sending it again."
        }
    }
}

public struct ImageAttachment: Identifiable, Equatable, Sendable {
    public static let maxCount = 8
    public static let maxBytes = 10 * 1024 * 1024
    public let id = UUID()
    public let name: String
    public let mimeType: String
    public let data: Data

    public init(name: String, mimeType: String, data: Data) {
        self.name = name
        self.mimeType = mimeType
        self.data = data
    }
}

public struct ThreadReference: Codable, Equatable, Sendable {
    public let threadId: String
    public let link: URL?
    public let environmentID: String?
    public let machineName: String?
    public let projectName: String?

    public init(
        threadId: String, link: URL?, environmentID: String? = nil,
        machineName: String? = nil, projectName: String? = nil
    ) {
        self.threadId = threadId
        self.link = link
        self.environmentID = environmentID
        self.machineName = machineName
        self.projectName = projectName
    }

    public var desktopURL: URL? {
        guard let link else { return nil }
        if link.scheme == "t3code", link.host == "threads" { return link }
        guard let parts = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/")
        if link.scheme == "t3-thread", parts.host == "v2", path.count >= 2 {
            let id = threadId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return URL(string: "t3code://threads/\(path[0])/\(id)")
        }
        if ["https", "http"].contains(link.scheme ?? ""),
            path.count == 3, path[0] == "threads" {
            return URL(string: "t3code://threads/\(path[1])/\(path[2])")
        }
        return nil
    }
}

public struct T3ModelSelection: Codable, Hashable, Sendable {
    public let instanceId: String
    public let model: String
    public let options: [T3ModelOptionSelection]?

    public init(instanceId: String, model: String, options: [T3ModelOptionSelection]? = nil) {
        self.instanceId = instanceId
        self.model = model
        self.options = options
    }

    var arguments: [String: any Sendable] {
        var result: [String: any Sendable] = ["instanceId": instanceId, "model": model]
        if let options { result["options"] = options.map(\.arguments) }
        return result
    }

    public func matches(_ other: Self?) -> Bool {
        instanceId == other?.instanceId && model == other?.model
    }

    public var fallbackLabel: String {
        guard model.hasPrefix("gpt-") else { return model }
        let parts = model.dropFirst(4).split(separator: "-")
        return "GPT-" + parts.map { $0.capitalized }.joined(separator: " ")
    }
}

public struct T3ModelOptionSelection: Codable, Hashable, Sendable {
    public let id: String
    public let value: String

    public init(id: String, value: String) {
        self.id = id
        self.value = value
    }

    var arguments: [String: String] { ["id": id, "value": value] }
}

public enum T3ModelOptionValue: Codable, Hashable, Sendable {
    case string(String)
    case boolean(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .boolean(try container.decode(Bool.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        }
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

public struct T3ModelOption: Codable, Equatable, Sendable {
    public let id: String
    public let values: [T3ModelOptionValue]
    public let defaultValue: T3ModelOptionValue?

    enum CodingKeys: String, CodingKey {
        case id, values
        case defaultValue = "default"
    }

    public var isEffort: Bool {
        let normalized = id.lowercased().filter(\.isLetter)
        return normalized == "effort" || normalized == "reasoningeffort"
    }

    public var stringValues: [String] { values.compactMap(\.string) }
    public var defaultString: String? { defaultValue?.string }
}

public struct T3Model: Identifiable, Equatable, Sendable {
    public var id: T3ModelSelection { selection }
    public let selection: T3ModelSelection
    public let label: String
    public let provider: String
    public let driverKind: String
    public let options: [T3ModelOption]

    public var effortOption: T3ModelOption? { options.first(where: \.isEffort) }

    public var shortLabel: String {
        let brand: String?
        switch driverKind {
        case "claudeAgent": brand = "Claude"
        case "codex": brand = "Codex"
        case "antigravity": brand = "Antigravity"
        case "cursor": brand = "Cursor"
        case "opencode": brand = "OpenCode"
        default: brand = nil
        }
        for prefix in [provider, brand].compactMap({ $0 }).sorted(by: { $0.count > $1.count }) {
            if let range = label.range(of: prefix + " ", options: [.anchored, .caseInsensitive]),
                range.upperBound != label.endIndex {
                return String(label[range.upperBound...])
            }
        }
        return label
    }

    public static func preferred(in models: [Self], saved: T3ModelSelection? = nil) -> Self? {
        models.first { $0.selection.matches(saved) }
            ?? models.first { $0.selection.instanceId == "claudeAgent" && $0.selection.model == "claude-opus-5-5" }
            ?? models.first { $0.selection.instanceId == "codex" && $0.selection.model == "gpt-6.1-sol" }
            ?? models.first
    }
}

public struct T3ModelProvider: Identifiable, Equatable, Sendable {
    public var id: String { instanceId }
    public let instanceId: String
    public let driverKind: String
    public let displayName: String
    public let constraints: [String]
    public let runtimeModes: [String]?
    public let omittedModels: Int
    public let models: [T3Model]

    public var enabled: Bool {
        constraints.isEmpty && (runtimeModes?.contains("approval-required") ?? true)
    }

    public var disabledReason: String? {
        if let constraint = constraints.first { return constraint }
        if runtimeModes?.contains("approval-required") == false {
            return "This provider does not support approval-required runs."
        }
        return nil
    }
}

public struct T3ModelCatalogue: Equatable, Sendable {
    public let providers: [T3ModelProvider]

    public var available: [T3Model] {
        providers.filter(\.enabled).flatMap(\.models)
    }
}

struct T3ModelCatalog: Decodable, Sendable {
    struct Provider: Decodable, Sendable {
        struct Model: Decodable, Sendable {
            let id: String
            let label: String?
            let options: [T3ModelOption]?
        }

        let providerInstanceId: String
        let driverKind: String
        let displayName: String?
        let constraints: [String]
        let runtimeModes: [String]?
        let omittedModels: Int?
        let models: [Model]
    }

    let providers: [Provider]

    var catalogue: T3ModelCatalogue {
        T3ModelCatalogue(providers: providers.map { provider in
            let name = provider.displayName ?? provider.driverKind
            return T3ModelProvider(
                instanceId: provider.providerInstanceId,
                driverKind: provider.driverKind,
                displayName: name,
                constraints: provider.constraints,
                runtimeModes: provider.runtimeModes,
                omittedModels: provider.omittedModels ?? 0,
                models: provider.models.map { model in
                    let selection = T3ModelSelection(instanceId: provider.providerInstanceId, model: model.id)
                    return T3Model(
                        selection: selection, label: model.label ?? selection.fallbackLabel,
                        provider: name, driverKind: provider.driverKind, options: model.options ?? []
                    )
                }
            )
        })
    }
}

public struct ThreadReceipt: Sendable {
    public let reference: ThreadReference
    public let runId: String
    public let status: RunStatus
    public let modelSelection: T3ModelSelection?
    public let projectID: String?
}

public enum RunStatus: Equatable, Sendable {
    case idle, running, waiting, completed, failed, stopped, unknown

    init(_ value: String) {
        switch value {
        case "idle": self = .idle
        case "preparing", "queued", "starting", "running": self = .running
        case "waiting": self = .waiting
        case "completed": self = .completed
        case "failed": self = .failed
        case "interrupted", "cancelled", "rolled_back": self = .stopped
        default: self = .unknown
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }
}

extension RunStatus: Decodable {}

public struct ThreadSnapshot: Decodable, Sendable {
    public struct Run: Decodable, Sendable {
        public let runId: String
        public let status: RunStatus
        public let failureReason: String?
    }

    public struct Thread: Decodable, Sendable {
        public let projectId: String
        public let title: String
        public let status: RunStatus
        public let pendingRequestCount: Int
        public let link: URL?
        public let providerInstanceId: String?
        public let model: String?

        public var modelSelection: T3ModelSelection? {
            guard let providerInstanceId, let model else { return nil }
            return T3ModelSelection(instanceId: providerInstanceId, model: model)
        }
    }

    public struct Item: Decodable, Identifiable, Sendable {
        public var id: String { itemId }
        public let itemId: String
        public let messageId: String?
        public let runId: String?
        public let position: Int
        public let type: String
        public let status: String
        public let text: String?
        public let textTruncated: Bool
        public let nextTextOffset: Int?
        public let updatedAt: String

        public var date: Date? { t3Date(updatedAt) }
    }

    public let thread: Thread
    public let items: [Item]
    public let recentRuns: [Run]?
    public let earlierPosition: Int?
}

func t3Date(_ value: String) -> Date? {
    (try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
        ?? (try? Date(value, strategy: .iso8601))
}
