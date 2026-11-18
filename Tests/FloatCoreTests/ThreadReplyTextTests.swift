import Foundation
import Testing

@testable import FloatCore

private func timelineItem(
    _ type: String, position: Int, text: String, status: String = "completed", truncated: Bool = false
) throws -> ThreadSnapshot.Item {
    let data = try JSONSerialization.data(withJSONObject: [
        "type": type, "itemId": "item-\(position)", "position": position, "text": text,
        "status": status, "textTruncated": truncated, "updatedAt": "2026-11-18T08:00:00Z",
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
    #expect(MarkdownBlockParser.parse(code) == [.code(language: "python", text: "name = \"Float\"\nprint(name)")])
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
