import Foundation
import Testing

@testable import FloatCore

private func timelineItem(
    _ type: String, position: Int, text: String, status: String = "completed", truncated: Bool = false,
    runId: String? = nil
) throws -> ThreadSnapshot.Item {
    let data = try JSONSerialization.data(withJSONObject: [
        "type": type, "itemId": "item-\(position)", "position": position, "text": text,
        "status": status, "textTruncated": truncated, "updatedAt": "2026-11-18T08:00:00Z",
        "runId": runId as Any? ?? NSNull(),
    ])
    return try JSONDecoder().decode(ThreadSnapshot.Item.self, from: data)
}

@Test func displaysOnlyT3SentMarkdownAlongsideAssistantMessages() throws {
    let code = "```python\nname = \"Float\"\nprint(name)\n```"
    let tool = try JSONSerialization.data(withJSONObject: [
        "toolName": "mcp__t3-code__send_to_user",
        "input": ["message": code],
        "output": ["structuredContent": ["sentMessage": code]],
    ])
    let timeline = try [
        timelineItem("assistant_message", position: 0, text: "Here is an example."),
        timelineItem("dynamic_tool", position: 1, text: #"{"toolName":"mcp__other__send_to_user","input":{"message":"Hidden"}}"#),
        timelineItem("dynamic_tool", position: 2, text: String(decoding: tool, as: UTF8.self)),
        timelineItem("command_execution", position: 3, text: "Hidden"),
        timelineItem("assistant_message", position: 4, text: "It prints the name."),
    ]
    #expect(timeline.compactMap { $0.chatText() } == ["Here is an example.", code, "It prints the name."])
    #expect(timeline.filter(\.isChatMessageCandidate).map(\.position) == [0, 2, 4])
    #expect(ChatMarkdown.parse(code) == [.code(language: "python", text: "name = \"Float\"\nprint(name)")])
}

@Test func expandsOnlyRelevantTruncatedToolsAndHidesFailedCalls() throws {
    let sent = try timelineItem("dynamic_tool", position: 0, text: """
        {
          "toolName": "mcp__t3-code__send_to_user",
          "input": {"message":"Incomplete
        """, truncated: true)
    let other = try timelineItem("dynamic_tool", position: 1, text: #"{"toolName":"search","input":"…"#, truncated: true)
    let failed = try timelineItem("dynamic_tool", position: 2, text: #"{"toolName":"send_to_user","input":{"message":"Hidden"},"output":{"isError":true}}"#)
    #expect(sent.isChatMessageCandidate)
    #expect(!other.isChatMessageCandidate)
    #expect(failed.chatText() == nil)
    #expect(sent.chatText(expandedText: #"{"toolName":"send_to_user","input":{"message":"Complete"}}"#) == "Complete")
}

@Test func groupsVisibleTextByTurnInMarkdownOrder() throws {
    let sentMarkdown = "```python\nprint('Float')\n```"
    let sentTool = try JSONSerialization.data(withJSONObject: [
        "toolName": "mcp__t3-code__send_to_user",
        "input": ["message": sentMarkdown],
    ])
    let timeline = try [
        timelineItem("user_message", position: 0, text: "Show me.", runId: "first"),
        timelineItem("assistant_message", position: 1, text: "An **example**.", runId: "first"),
        timelineItem("command_execution", position: 2, text: "Hidden", runId: "first"),
        timelineItem("dynamic_tool", position: 3, text: String(decoding: sentTool, as: UTF8.self), runId: "first"),
        timelineItem("assistant_message", position: 4, text: "It prints the name.", runId: "first"),
        timelineItem("user_message", position: 5, text: "Thanks.", runId: "second"),
        timelineItem("assistant_message", position: 6, text: "You're welcome.", runId: "second"),
        timelineItem("assistant_message", position: 7, text: "A follow-up.", runId: "third"),
    ]
    let messages = timeline.compactMap { item -> ChatMessage? in
        guard let text = item.chatText() else { return nil }
        return ChatMessage(
            id: item.id, runId: item.runId, position: item.position,
            isUser: item.type == "user_message", text: text, date: item.date, previews: []
        )
    }

    let grouped = ChatMessage.groupReplies(in: messages)
    #expect(grouped.map(\.id) == ["item-0", "item-1", "item-5", "item-6", "item-7"])
    #expect(grouped.filter(\.isUser) == messages.filter(\.isUser))
    #expect(grouped.filter { !$0.isUser }.map(\.text) == [
        "An **example**.\n\n\(sentMarkdown)\n\nIt prints the name.",
        "You're welcome.",
        "A follow-up.",
    ])
}

@Test func regroupingUsesUpdatedPartsAndKeepsRepliesWithoutRunIDsSeparate() {
    func reply(_ id: String, runId: String?, text: String, date: Date? = nil) -> ChatMessage {
        ChatMessage(id: id, runId: runId, position: 0, isUser: false, text: text, date: date, previews: [])
    }

    let time = Date(timeIntervalSince1970: 100)
    let beginning = reply("start", runId: "turn", text: "Starting.")
    let partial = reply("end", runId: "turn", text: "St")
    let complete = reply("end", runId: "turn", text: "Stopped.", date: time)
    let legacy = [reply("older", runId: nil, text: "Older."), reply("old", runId: nil, text: "Old.")]

    #expect(ChatMessage.groupReplies(in: [beginning, partial]).first?.text == "Starting.\n\nSt")
    let updated = ChatMessage.groupReplies(in: legacy + [beginning, complete])
    #expect(Array(updated.dropLast()) == legacy)
    #expect(updated.last?.id == beginning.id)
    #expect(updated.last?.date == time)
    #expect(updated.last?.text == "Starting.\n\nStopped.")
}

@Test func omitsBlankAssistantTurnsAndKeepsImageOnlyUserMessages() {
    let user = ChatMessage(id: "image", runId: "question", position: 0, isUser: true,
                           text: "", date: nil, previews: [Data([1])])
    let blank = ChatMessage(id: "empty", runId: "question", position: 1, isUser: false,
                            text: " \t\n", date: Date(timeIntervalSince1970: 100), previews: [])
    let later = ChatMessage(id: "reply", runId: "follow-up", position: 2, isUser: false,
                            text: "A visible reply.", date: nil, previews: [])

    #expect(ChatMessage.groupReplies(in: [user, blank, later]) == [user, later])
}
