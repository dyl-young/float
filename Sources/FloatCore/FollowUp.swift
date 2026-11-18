import Foundation

public enum FollowUpMode: String, Codable, Sendable {
    case steer, queue

    public func resolved(alternate: Bool, canSteer: Bool) -> Self {
        guard canSteer else { return .queue }
        guard alternate else { return self }
        return self == .steer ? .queue : .steer
    }

    public static func setting(in data: Data?) -> Self {
        struct Settings: Decodable { let followUpBehavior: FollowUpMode }
        guard let data, let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return .steer }
        return settings.followUpBehavior
    }
}

public enum FollowUpState: Equatable, Sendable {
    case steerWaiting, steerRead, queued

    public init?(inputIntent: String?, status: String, knownSteer: Bool) {
        guard knownSteer || inputIntent == "steer" || inputIntent == "promoted_queued_to_steer" else {
            return nil
        }
        // T3 moves the input item from pending when the provider acknowledges it.
        self = status == "pending" ? .steerWaiting : .steerRead
    }
}

public struct T3QueuedFollowUp: Decodable, Equatable, Sendable {
    public let queuedRunId: String
    public let text: String
}

public struct T3FollowUpCapabilities: Decodable, Sendable {
    public let supportsActiveSteering: Bool
    public let activeSteeringAcceptsAttachments: Bool?
    public let activeSteeringDuringCompaction: Bool?

    public init(supportsActiveSteering: Bool, activeSteeringAcceptsAttachments: Bool? = nil,
                activeSteeringDuringCompaction: Bool? = nil) {
        self.supportsActiveSteering = supportsActiveSteering
        self.activeSteeringAcceptsAttachments = activeSteeringAcceptsAttachments
        self.activeSteeringDuringCompaction = activeSteeringDuringCompaction
    }
}

public struct T3FollowUpProjection: Decodable, Sendable {
    private struct Run: Decodable { let id: String; let providerThreadId: String? }
    private struct ProviderThread: Decodable { let id: String; let providerSessionId: String? }
    private struct Session: Decodable {
        struct Capabilities: Decodable { let turns: T3FollowUpCapabilities }
        let id: String
        let capabilities: Capabilities
    }
    private struct Message: Decodable { let id: String; let inputIntent: String? }

    private let runs: [Run]
    private let providerThreads: [ProviderThread]
    private let providerSessions: [Session]
    private let messages: [Message]

    public var steeredMessageIDs: [String] {
        messages.filter { $0.inputIntent == "steer" || $0.inputIntent == "promoted_queued_to_steer" }.map(\.id)
    }

    public func capabilities(for runID: String) -> T3FollowUpCapabilities? {
        let providerThread = runs.first { $0.id == runID }?.providerThreadId
        let session = providerThreads.first { $0.id == providerThread }?.providerSessionId
        return providerSessions.first { $0.id == session }?.capabilities.turns
    }
}
