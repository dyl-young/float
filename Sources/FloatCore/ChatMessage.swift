import Foundation

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let runId: String?
    public let position: Int
    public let isUser: Bool
    public private(set) var text: String
    public private(set) var date: Date?
    public let previews: [Data]

    public init(
        id: String, runId: String?, position: Int, isUser: Bool,
        text: String, date: Date?, previews: [Data]
    ) {
        self.id = id
        self.runId = runId
        self.position = position
        self.isUser = isUser
        self.text = text
        self.date = date
        self.previews = previews
    }

    /// Group the visible messages in timeline order. The original items stay available
    /// for streaming updates and pages that start partway through a turn.
    public static func groupReplies(in messages: [Self]) -> [Self] {
        var grouped: [Self] = []
        for message in messages {
            guard message.isUser || message.text.contains(where: { !$0.isWhitespace }) else { continue }
            if !message.isUser, let runId = message.runId, let last = grouped.indices.last,
                !grouped[last].isUser, grouped[last].runId == runId {
                grouped[last].text += "\n\n" + message.text
                if let date = message.date { grouped[last].date = date }
            } else {
                grouped.append(message)
            }
        }
        return grouped
    }
}
