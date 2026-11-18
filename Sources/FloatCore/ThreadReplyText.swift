import Foundation

extension ThreadSnapshot.Item {
    public var isChatMessageCandidate: Bool {
        if type == "user_message" || type == "assistant_message" { return true }
        guard type == "dynamic_tool", status == "completed", let text else { return false }
        if textTruncated {
            // T3 serializes dynamic tools with toolName as the first JSON property.
            let pattern = #"^\s*\{\s*"toolName"\s*:\s*"([^"]+)""#
            guard let range = text.range(of: pattern, options: .regularExpression),
                  let toolName = text[range].split(separator: "\"").last else { return false }
            return Self.isSendToUser(String(toolName))
        }
        return Self.decodeTool(text).map { Self.isSendToUser($0.toolName) } ?? false
    }

    public func chatText(expandedText: String? = nil) -> String? {
        if type == "user_message" || type == "assistant_message" { return expandedText ?? text }
        guard type == "dynamic_tool", status == "completed", let raw = expandedText ?? text,
              let tool = Self.decodeTool(raw), Self.isSendToUser(tool.toolName),
              tool.output?.isError != true else { return nil }
        return tool.output?.structuredContent?.sentMessage ?? tool.output?.sentMessage ?? tool.input?.message
    }

    private struct Tool: Decodable {
        struct Input: Decodable { let message: String? }
        struct Output: Decodable {
            struct Content: Decodable { let sentMessage: String? }
            let isError: Bool?
            let sentMessage: String?
            let structuredContent: Content?
        }

        let toolName: String
        let input: Input?
        let output: Output?

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            toolName = try values.decode(String.self, forKey: .toolName)
            input = try? values.decode(Input.self, forKey: .input)
            if let serialized = try? values.decode(String.self, forKey: .output) {
                output = try? JSONDecoder().decode(Output.self, from: Data(serialized.utf8))
            } else {
                output = try? values.decode(Output.self, forKey: .output)
            }
        }

        private enum CodingKeys: String, CodingKey { case toolName, input, output }
    }

    private static func isSendToUser(_ name: String) -> Bool {
        let pattern = #"^(?:(?:mcp__t3[-_]code(?:[-_]direct)?__|t3[-_]?code(?:[-_]direct)?[.:/]))?send_to_user$"#
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func decodeTool(_ text: String) -> Tool? {
        try? JSONDecoder().decode(Tool.self, from: Data(text.utf8))
    }
}
