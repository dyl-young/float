import Foundation

public struct T3Machine: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case local
        case linked
    }

    public enum Status: String, Codable, Sendable {
        case reachable
        case unreachable
        case expired
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let status: Status
    public let projectCount: Int?

    public init(
        id: String, name: String, kind: Kind, status: Status,
        projectCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.projectCount = projectCount
    }

    public var isLocal: Bool { kind == .local }
    public var isOnline: Bool { isLocal || status == .reachable }
}

public enum T3MachinePicker {
    public static func ordered(_ machines: [T3Machine]) -> [T3Machine] {
        machines.sorted {
            if $0.isLocal != $1.isLocal { return $0.isLocal }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func resolvedID(_ savedID: String?, machines: [T3Machine]) -> String? {
        if let savedID, machines.contains(where: { $0.id == savedID && $0.isOnline }) {
            return savedID
        }
        return machines.first(where: \.isLocal)?.id
    }
}
