import Foundation
import Markdown

public struct MarkdownSpan: Equatable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    public var struck = false
    public var code = false
    public var link: URL?

    public init(_ text: String) {
        self.text = text
    }
}

public struct MarkdownListItem: Equatable, Sendable {
    public let checked: Bool?
    public let blocks: [MarkdownBlock]
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case leading, center, trailing
    }

    public let alignments: [Alignment]
    public let rows: [[[MarkdownSpan]]]
}

public enum MarkdownBlock: Equatable, Sendable {
    case paragraph([MarkdownSpan])
    case heading(level: Int, spans: [MarkdownSpan])
    case list(start: UInt?, items: [MarkdownListItem])
    case quote([MarkdownBlock])
    case rule
    case table(MarkdownTable)
    case code(language: String?, text: String)
}

public enum ChatMarkdown {
    public static func parse(_ source: String, preserveLineBreaks: Bool = false) -> [MarkdownBlock] {
        let converter = Converter(lines: source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline),
                                  softBreak: preserveLineBreaks ? "\n" : " ")
        return Document(parsing: source, options: [.disableSmartOpts]).children.compactMap(converter.block)
    }
}

private struct Converter {
    let lines: [Substring]
    let softBreak: String

    func block(_ markup: any Markup) -> MarkdownBlock? {
        switch markup {
        case let paragraph as Paragraph:
            return .paragraph(spans(in: paragraph))
        case let heading as Heading:
            return .heading(level: heading.level, spans: spans(in: heading))
        case let list as OrderedList:
            return .list(start: list.startIndex, items: list.listItems.map(listItem))
        case let list as UnorderedList:
            return .list(start: nil, items: list.listItems.map(listItem))
        case let quote as BlockQuote:
            return .quote(quote.children.compactMap(block))
        case is ThematicBreak:
            return .rule
        case let table as Table:
            let alignments: [MarkdownTable.Alignment] = table.columnAlignments.map {
                switch $0 {
                case .center: .center
                case .right: .trailing
                default: .leading
                }
            }
            let rows = [table.head.children.map { spans(in: $0) }]
                + table.body.children.map { $0.children.map { spans(in: $0) } }
            return .table(MarkdownTable(alignments: alignments, rows: rows))
        case let code as CodeBlock:
            let text = code.code
            return .code(language: code.language, text: text.hasSuffix("\n") ? String(text.dropLast()) : text)
        case let html as HTMLBlock:
            return .paragraph([MarkdownSpan(html.rawHTML.trimmingCharacters(in: .newlines))])
        default:
            return nil
        }
    }

    private func listItem(_ item: ListItem) -> MarkdownListItem {
        let blocks = item.children.compactMap(block)
        if let checkbox = item.checkbox {
            return MarkdownListItem(checked: checkbox == .checked, blocks: blocks)
        }
        // Some container prefixes (for example a blockquote) prevent cmark
        // from recognizing the task marker. Check the original first token
        // so escaped brackets and a link named "[x]" still render literally.
        guard let location = item.child(at: 0)?.child(at: 0)?.range?.lowerBound,
              lines.indices.contains(location.line - 1),
              case .paragraph(var spans) = blocks.first, let first = spans.first,
              first.link == nil, !first.code else {
            return MarkdownListItem(checked: nil, blocks: blocks)
        }
        let prefix = String(decoding: lines[location.line - 1].utf8.dropFirst(location.column - 1).prefix(4), as: UTF8.self)
        let marker = prefix.lowercased()
        guard marker == "[x] " || marker == "[ ] ", first.text.hasPrefix(prefix) else {
            return MarkdownListItem(checked: nil, blocks: blocks)
        }
        spans[0].text = String(first.text.dropFirst(4))
        if spans[0].text.isEmpty { spans.removeFirst() }
        return MarkdownListItem(checked: marker == "[x] ", blocks: [.paragraph(spans)] + blocks.dropFirst())
    }

    private func spans(in parent: any Markup, style: MarkdownSpan = MarkdownSpan("")) -> [MarkdownSpan] {
        parent.children.flatMap { child -> [MarkdownSpan] in
            var span = style
            switch child {
            case let text as Markdown.Text:
                span.text = text.string
                return autolinks(in: span)
            case is SoftBreak:
                span.text = softBreak
                return [span]
            case is LineBreak:
                span.text = "\n"
                return [span]
            case let code as InlineCode:
                span.text = code.code
                span.code = true
                return [span]
            case let html as InlineHTML:
                span.text = html.rawHTML
                return [span]
            case is Strong:
                span.bold = true
            case is Emphasis:
                span.italic = true
            case is Strikethrough:
                span.struck = true
            case let link as Link:
                span.link = webURL(link.destination)
            case let image as Image:
                span.text = image.plainText.isEmpty ? image.source ?? "" : image.plainText
                span.link = webURL(image.source) ?? style.link
                return [span]
            default:
                break
            }
            return spans(in: child, style: span)
        }
    }

    private func webURL(_ destination: String?) -> URL? {
        guard let destination,
              let url = URL(string: destination.hasPrefix("//") ? "https:\(destination)" : destination),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme) else { return nil }
        return url
    }

    // swift-markdown does not enable cmark-gfm's bare autolink extension.
    // Match bare links in text spans so code, HTML and explicit links keep their own handling.
    private static let bareLinks = try? NSRegularExpression(pattern: #"""
        (?ix)
        (?<web> (?<![^\s*_~(]) (?:https?://|www\.) [\p{L}\p{N}][^\s<]* )
        |
        (?<![a-z0-9_.+@-]) [a-z0-9_.+-]+@ (?:[a-z0-9_-]+\.)+ [a-z0-9_-]*[a-z0-9]
        (?![a-z0-9_-]|\.[a-z0-9_-])
        """#)

    private func autolinks(in span: MarkdownSpan) -> [MarkdownSpan] {
        let text = span.text
        guard span.link == nil, text.contains(".") || text.contains("@") || text.contains("://"),
              let bareLinks = Self.bareLinks else { return [span] }
        var result: [MarkdownSpan] = []
        var start = text.startIndex
        for match in bareLinks.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let candidate = text[range]
            let isWeb = match.range(withName: "web").location != NSNotFound
            let label = isWeb ? trimWebLink(candidate) : candidate
            let prefix = isWeb ? (label.lowercased().hasPrefix("www.") ? "http://" : "") : "mailto:"
            guard let url = webURL(prefix + label) else { continue }
            if start < range.lowerBound {
                var preceding = span
                preceding.text = String(text[start..<range.lowerBound])
                result.append(preceding)
            }
            var link = span
            link.text = String(label)
            link.link = url
            result.append(link)
            start = label.endIndex
        }
        if start == text.startIndex { return [span] }
        if start < text.endIndex {
            var suffix = span
            suffix.text = String(text[start...])
            result.append(suffix)
        }
        return result
    }

    private func trimWebLink(_ candidate: Substring) -> Substring {
        var link = candidate
        var excessClosers = candidate.reduce(into: 0) { balance, character in
            if character == ")" { balance += 1 }
            if character == "(" { balance -= 1 }
        }
        while let last = link.last {
            if last == ")", excessClosers > 0 {
                excessClosers -= 1
            } else if !"?!.:,*_~'\"".contains(last) {
                break
            }
            link = link.dropLast()
        }
        return link
    }
}
