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

@Test func distinguishesScratchFromARegularLocalProject() {
    let base = URL(fileURLWithPath: "/tmp/float-test-home", isDirectory: true)
    let client = T3Client(base: base)
    let scratch = T3Project(id: "scratch", title: "No project", workspaceRoot: base.appending(path: "scratch").path)
    let project = T3Project(id: "regular", title: "No project", workspaceRoot: "/tmp/regular")
    #expect(client.isScratchProject(scratch, environmentID: nil))
    #expect(!client.isScratchProject(project, environmentID: nil))
    #expect(client.isScratchProject(scratch, environmentID: "remote"))
}

@Test func derivesFirstSendTitleFromTheMessageOrAttachment() {
    #expect(T3Client.launchTitle(for: "First line\nSecond line", attachmentName: "Screenshot.png") == "First line")
    #expect(T3Client.launchTitle(for: "", attachmentName: "Screenshot.png") == "Screenshot.png")
    #expect(T3Client.launchTitle(for: "", attachmentName: nil) == "Float chat")
    #expect(T3Client.launchTitle(for: String(repeating: "a", count: 81), attachmentName: nil).count == 80)
}
