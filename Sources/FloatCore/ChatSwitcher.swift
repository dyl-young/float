import Foundation

public struct T3ThreadListItem: Decodable, Sendable {
    public let threadId: String
    public let projectId: String
    public let title: String
    private let link: String?
    public let status: RunStatus
    public let latestRunId: String?
    let providerInstanceId: String
    let model: String
    let settled: Bool?
    let settledAt: String?
    let archivedAt: String?
    let archived: Bool?
    let snoozed: Bool?
    let snoozedUntil: String?
    let pinned: Bool?
    let pinnedAt: String?
    let relationshipToParent: String?
    let delegatedFrom: Delegation?
    let updatedAt: String

    struct Delegation: Decodable, Sendable {}

    var linkURL: URL? {
        guard let link else { return nil }
        var destination = link[...]
        // T3 returns either a labeled Markdown link or an autolink.
        if let marker = link.range(of: "](", options: .backwards), link.hasSuffix(")") {
            destination = link[marker.upperBound..<link.index(before: link.endIndex)]
        }
        if destination.hasPrefix("<"), destination.hasSuffix(">") {
            destination = destination.dropFirst().dropLast()
        }
        return URL(string: String(destination))
    }

    public var modelSelection: T3ModelSelection {
        T3ModelSelection(instanceId: providerInstanceId, model: model)
    }
}

public struct ChatSwitcherEntry: Identifiable, Sendable {
    public struct ID: Hashable, Sendable {
        public let environmentID: String?
        public let threadID: String

        public init(_ reference: ThreadReference) {
            environmentID = reference.environmentID
            threadID = reference.threadId
        }
    }

    public let thread: T3ThreadListItem
    public let reference: ThreadReference
    public let project: T3Project?
    public let runStartedAt: Date?

    public init(
        thread: T3ThreadListItem, reference: ThreadReference, project: T3Project?, runStartedAt: Date? = nil
    ) {
        self.thread = thread
        self.reference = reference
        self.project = project
        self.runStartedAt = runStartedAt
    }

    public var id: ID { ID(reference) }
    public var title: String { ChatTitle.plainText(thread.title) }
    public var projectName: String { project?.title ?? reference.projectName ?? "No project" }
    public var updatedAt: Date? { t3Date(thread.updatedAt) }

    fileprivate func group(at now: Date) -> ChatSwitcherGroup.Kind? {
        guard thread.settled != true, thread.settledAt == nil,
              thread.archived != true, thread.archivedAt == nil,
              thread.snoozed != true, thread.snoozedUntil.flatMap(t3Date).map({ $0 > now }) != true,
              thread.relationshipToParent != "subagent", thread.delegatedFrom == nil else { return nil }
        if thread.status.isInProgress { return .working }
        if thread.pinned == true || thread.pinnedAt != nil { return .pinned }
        return .active
    }
}

public struct ChatSwitcherGroup: Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case working = "Working"
        case pinned = "Pinned"
        case active = "Active"
    }

    public let id: Kind
    public let entries: [ChatSwitcherEntry]

    public static func group(_ entries: [ChatSwitcherEntry], now: Date = .now) -> [Self] {
        let ordered = entries.map { ($0, $0.updatedAt ?? .distantPast) }.sorted { $0.1 > $1.1 }
        var seen = Set<ChatSwitcherEntry.ID>()
        var groups: [Kind: [ChatSwitcherEntry]] = [:]
        for (entry, _) in ordered where seen.insert(entry.id).inserted {
            guard let kind = entry.group(at: now) else { continue }
            groups[kind, default: []].append(entry)
        }
        return Kind.allCases.compactMap { kind in
            groups[kind].map { Self(id: kind, entries: $0) }
        }
    }

    public static func filter(_ groups: [Self], query: String) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let entries = group.entries.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.projectName.localizedCaseInsensitiveContains(query)
            }
            return entries.isEmpty ? nil : Self(id: group.id, entries: entries)
        }
    }
}

public struct ChatSwitcherCatalog: Sendable {
    public let groups: [ChatSwitcherGroup]
    public let hasUnavailableMachines: Bool
}
