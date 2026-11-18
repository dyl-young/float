import Foundation
import Testing
@testable import FloatCore

struct ChatSwitcherTests {
    @Test func groupsByPriorityAndOrdersByLastUpdate() throws {
        let entries = try [
            entry("active", status: "completed", day: 6),
            entry("waiting", status: "waiting", day: 4),
            entry("running-pin", status: "running", pinned: true, day: 3),
            entry("queued", status: "queued", day: 5),
            entry("starting", status: "starting", day: 2),
            entry("preparing", status: "preparing", day: 1),
            entry("pinned", pinned: true, day: 7),
            entry("older"),
        ]
        let groups = ChatSwitcherGroup.group(entries)
        #expect(groups.map(\.id) == [.working, .pinned, .active])
        #expect(threadIDs(groups[0].entries) == ["queued", "waiting", "running-pin", "starting", "preparing"])
        #expect(threadIDs(groups[1].entries) == ["pinned"])
        #expect(threadIDs(groups[2].entries) == ["active", "older"])
    }

    @Test func excludesHiddenThreadsEvenWhenPinnedOrRunning() throws {
        let entries = try [
            entry("settled", status: "running", extra: ["settled": true]),
            entry("settled-time", pinned: true, extra: ["settledAt": "2026-11-02T10:00:00Z"]),
            entry("archive", pinned: true, extra: ["archived": true]),
            entry("archive-time", extra: ["archivedAt": "2026-11-03T10:00:00Z"]),
            entry("snooze", status: "queued", extra: ["snoozed": true]),
            entry("snooze-until", extra: ["snoozedUntil": "2026-11-05T10:00:00Z"]),
            entry("expired", extra: ["snoozedUntil": "2026-11-03T10:00:00Z"]),
            entry("subagent", extra: ["relationshipToParent": "subagent"]),
            entry("remote-delegate", extra: ["delegatedFrom": ["environmentId": "mac"]]),
            entry("fork", extra: ["relationshipToParent": "fork"]),
        ]
        let now = try #require(t3Date("2026-11-04T10:00:00Z"))
        let groups = ChatSwitcherGroup.group(entries, now: now)
        #expect(groups.map(\.id) == [.active])
        #expect(Set(threadIDs(groups.flatMap(\.entries))) == ["expired", "fork"])
    }

    @Test func deduplicatesByMachineAndThreadUsingNewestRecord() throws {
        let entries = try [
            entry("same", status: "running", day: 1),
            entry("same", pinned: true, day: 2),
            entry("same", status: "running", day: 3, machine: "other"),
        ]
        let groups = ChatSwitcherGroup.group(entries)
        #expect(groups.map(\.id) == [.working, .pinned])
        #expect(groups.flatMap(\.entries).map(\.id.environmentID) == ["other", nil])
    }

    @Test func filtersByTitleOrProjectWithoutChangingOrder() throws {
        let entries = try [
            entry("One", pinned: true, project: "Float", day: 4),
            entry("Float resize", day: 3),
            entry("Two", project: "Float machine", day: 2, machine: "remote"),
            entry("Idle", day: 1),
        ]
        let groups = ChatSwitcherGroup.group(entries)
        let matching = ChatSwitcherGroup.filter(groups, query: " fLoAt ")
        #expect(matching.map(\.id) == [.pinned, .active])
        #expect(threadIDs(matching.flatMap(\.entries)) == ["One", "Float resize", "Two"])
        #expect(threadIDs(ChatSwitcherGroup.filter(groups, query: "No project").flatMap(\.entries)) == [
            "Float resize", "Idle",
        ])
        #expect(ChatSwitcherGroup.filter(groups, query: "missing").isEmpty)
    }

    @Test(arguments: [
        "[Float QA](t3-thread://v2/mac/test-thread)",
        "<t3-thread://v2/mac/test-thread>",
        "t3-thread://v2/mac/test-thread",
    ])
    func extractsTheDesktopDestinationFromThreadListLinks(link: String) throws {
        let reference = try entry("test-thread", extra: ["link": link]).reference
        #expect(reference.desktopURL?.absoluteString == "t3code://threads/mac/test-thread")
    }

    private func threadIDs(_ entries: [ChatSwitcherEntry]) -> [String] {
        entries.map(\.id.threadID)
    }

    private func entry(
        _ id: String, status: String = "idle", pinned: Bool = false, project: String? = nil,
        day: Int = 1, machine: String? = nil, extra: [String: Any] = [:]
    ) throws -> ChatSwitcherEntry {
        let fields: [String: Any] = [
            "threadId": id, "projectId": "project-id", "title": id, "status": status,
            "pinned": pinned, "updatedAt": "2026-11-0\(day)T10:00:00Z",
            "providerInstanceId": "provider", "model": "model",
        ]
        let data = try JSONSerialization.data(withJSONObject: fields.merging(extra) { _, value in value })
        let thread = try JSONDecoder().decode(T3ThreadListItem.self, from: data)
        return ChatSwitcherEntry(
            thread: thread, reference: ThreadReference(
                threadId: id, link: thread.linkURL, environmentID: machine, machineName: machine, projectName: project
            ), project: nil
        )
    }
}
