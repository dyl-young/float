import Foundation
import Testing

@testable import FloatCore

private let projectHome = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

private func project(
    _ id: String, title: String, path: String, archivedAt: String? = nil
) -> T3Project {
    T3Project(
        id: id, title: title, workspaceRoot: path,
        archivedAt: archivedAt, deletedAt: nil
    )
}

@Test func projectSearchFiltersByNameAndPath() {
    let float = project("float", title: "Float", path: "/Users/tester/dev/float")
    let reports = project("reports", title: "Flow Reports", path: "/Users/tester/dev/flow-reports")
    let archived = project(
        "old", title: "Old Float", path: "/Users/tester/archive/float",
        archivedAt: "2026-11-18T00:00:00Z"
    )
    let projects = [float, reports, archived]

    #expect(T3ProjectSearch.filter(projects, query: "FLOAT") == [float])
    #expect(T3ProjectSearch.filter(projects, query: "flow-reports") == [reports])
    #expect(T3ProjectSearch.filter(projects, query: "archive").isEmpty)
    #expect(float.shortenedPath(homeDirectory: projectHome) == "~/dev/float")
}

@Test func projectPreferenceFallsBackWhenSavedProjectIsUnavailable() {
    let current = project("float", title: "Float", path: "/Users/tester/dev/float")
    let archived = project(
        "old", title: "Old Float", path: "/Users/tester/archive/float",
        archivedAt: "2026-11-18T00:00:00Z"
    )

    #expect(T3ProjectPreference.resolvedID("float", projects: [current, archived]) == "float")
    #expect(T3ProjectPreference.resolvedID("missing", projects: [current, archived]) == nil)
    #expect(T3ProjectPreference.resolvedID("old", projects: [current, archived]) == nil)
    #expect(T3ProjectPreference.resolvedID(nil, projects: [current]) == nil)
}
