import Foundation

public struct ComposerSkillChip: Codable, Equatable, Sendable {
    public let name: String
    public let label: String

    public init(name: String, label: String) {
        self.name = name
        self.label = label
    }

    public var token: String { "$" + name }

    // The same token boundary T3 uses to render skill mentions in messages.
    private static let mention = try! NSRegularExpression(
        pattern: #"(?<!\S)\$(?=[a-zA-Z0-9:_-]*[a-zA-Z])([a-zA-Z0-9][a-zA-Z0-9:_-]*)(?!\S)"#
    )

    public static func matches(
        in text: String, chips: [Self]
    ) -> [(range: Range<String.Index>, chip: Self)] {
        guard !chips.isEmpty, text.contains("$") else { return [] }
        let byName = Dictionary(chips.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return mention.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let name = Range(match.range(at: 1), in: text),
                  let chip = byName[String(text[name])] else { return nil }
            return (range, chip)
        }
    }
}

public struct ComposerDraft: Codable, Equatable, Sendable {
    public static let attachmentCharacter = "\u{fffc}"

    // Each chip occupies one UTF-16 code unit in the editor.
    public let editorText: String
    public let chips: [Int: ComposerSkillChip]

    public init(_ editorText: String = "", chips: [Int: ComposerSkillChip] = [:]) {
        self.editorText = editorText
        let source = editorText as NSString
        self.chips = chips.filter {
            $0.key >= 0 && $0.key < source.length && source.character(at: $0.key) == 0xfffc
        }
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try fields.decode(String.self, forKey: .editorText),
                  chips: try fields.decode([Int: ComposerSkillChip].self, forKey: .chips))
    }

    public var text: String {
        sendText(in: NSRange(location: 0, length: editorText.utf16.count))
    }

    public func sendText(in range: NSRange) -> String {
        let source = editorText as NSString
        guard range.location >= 0, range.length >= 0, range.location <= source.length,
              range.length <= source.length - range.location else { return "" }
        let result = NSMutableString(string: source.substring(with: range))
        for position in chips.keys.sorted(by: >) where NSLocationInRange(position, range) {
            if let chip = chips[position] {
                result.replaceCharacters(in: NSRange(location: position - range.location, length: 1),
                                         with: chip.token)
            }
        }
        return result as String
    }

    public func chipDeletionRange(before caret: Int) -> NSRange? {
        let source = editorText as NSString
        guard caret > 0, caret <= source.length else { return nil }
        if chips[caret - 1] != nil {
            return NSRange(location: caret - 1, length: 1)
        }
        // Selection inserts a separating space. Backspace beside that space
        // removes the chip and its separator in one edit.
        if caret > 1, chips[caret - 2] != nil, source.character(at: caret - 1) == 32 {
            return NSRange(location: caret - 2, length: 2)
        }
        return nil
    }
}
