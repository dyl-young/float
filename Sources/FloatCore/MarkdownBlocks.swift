import Foundation

public struct MarkdownOrderedItem: Equatable, Sendable {
    public let number: Int
    public let text: String

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(String)
    case unorderedList([String])
    case orderedList([MarkdownOrderedItem])
    case code(language: String?, text: String)
}

public enum MarkdownBlockParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let language = fenceLanguage(lines[index]) {
                index += 1
                var code: [String] = []
                while index < lines.count, !isFence(lines[index]) {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                continue
            }

            if let heading = headingText(lines[index]) {
                blocks.append(.heading(heading))
                index += 1
                continue
            }

            if unorderedItem(lines[index]) != nil {
                var items: [String] = []
                while index < lines.count, let item = unorderedItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if orderedItem(lines[index]) != nil {
                var items: [MarkdownOrderedItem] = []
                while index < lines.count, let item = orderedItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            var paragraph: [String] = []
            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty || startsBlock(line) { break }
                paragraph.append(line.trimmingCharacters(in: .whitespaces))
                index += 1
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            } else {
                index += 1
            }
        }
        return blocks
    }

    private static func startsBlock(_ line: String) -> Bool {
        fenceLanguage(line) != nil || headingText(line) != nil
            || unorderedItem(line) != nil || orderedItem(line) != nil
    }

    private static func fenceLanguage(_ line: String) -> String?? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else { return nil }
        let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? .some(nil) : .some(language)
    }

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private static func headingText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marks = trimmed.prefix(while: { $0 == "#" })
        guard (1...6).contains(marks.count), trimmed.dropFirst(marks.count).first == " " else { return nil }
        return trimmed.dropFirst(marks.count + 1).trimmingCharacters(in: .whitespaces)
    }

    private static func unorderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, "-*+".contains(marker) else { return nil }
        let remainder = trimmed.dropFirst()
        guard remainder.first?.isWhitespace == true else { return nil }
        return remainder.trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(_ line: String) -> MarkdownOrderedItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix(while: \.isNumber)
        guard let number = Int(digits), !digits.isEmpty else { return nil }
        let suffix = trimmed.dropFirst(digits.count)
        guard let delimiter = suffix.first, delimiter == "." || delimiter == ")" else { return nil }
        let remainder = suffix.dropFirst()
        guard remainder.first?.isWhitespace == true else { return nil }
        return MarkdownOrderedItem(number: number, text: remainder.trimmingCharacters(in: .whitespaces))
    }
}
