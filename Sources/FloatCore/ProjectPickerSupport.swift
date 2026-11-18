import Foundation

public struct T3ProjectIcon: Codable, Equatable, Sendable {
    public let kind: String
    public let text: String?
    public let emoji: String?
    public let color: String?
    public let name: String?
}

public struct T3Project: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let workspaceRoot: String
    public let faviconPath: String?
    public let projectIcon: T3ProjectIcon?
    public let archivedAt: String?
    public let deletedAt: String?

    public init(
        id: String, title: String, workspaceRoot: String,
        archivedAt: String? = nil, deletedAt: String? = nil,
        faviconPath: String? = nil, projectIcon: T3ProjectIcon? = nil
    ) {
        self.id = id
        self.title = title
        self.workspaceRoot = workspaceRoot
        self.faviconPath = faviconPath
        self.projectIcon = projectIcon
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
    }

    public var isAvailable: Bool { archivedAt == nil && deletedAt == nil }

    public func shortenedPath(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let home = homeDirectory.standardizedFileURL.path
        let path = URL(fileURLWithPath: workspaceRoot).standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

public enum T3ProjectSearch {
    public static func matches(_ project: T3Project, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return project.title.localizedCaseInsensitiveContains(query)
            || project.workspaceRoot.localizedCaseInsensitiveContains(query)
            || project.shortenedPath().localizedCaseInsensitiveContains(query)
    }

    public static func filter(_ projects: [T3Project], query: String) -> [T3Project] {
        projects.filter(\.isAvailable).filter { matches($0, query: query) }
    }
}

public enum T3ProjectPreference {
    public static func resolvedID(_ savedProjectID: String?, projects: [T3Project]) -> String? {
        guard let savedProjectID,
            projects.contains(where: { $0.id == savedProjectID && $0.isAvailable })
        else { return nil }
        return savedProjectID
    }
}
