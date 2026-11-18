import Foundation
import Testing
@testable import FloatCore

@Test func parsesMarkdownBlocks() {
    let blocks = ChatMarkdown.parse("""
    # Result

    Intro with [a link](https://example.com).

    - first item
    - second item

    3. third item
    4. fourth item

    ```swift
    let value = "a long line"
    print(value)
    ```
    """)

    guard case .heading(1, let heading) = blocks[0],
          case .paragraph(let intro) = blocks[1],
          case .list(nil, let bullets) = blocks[2],
          case .list(3, let numbered) = blocks[3] else {
        Issue.record("Expected a heading, paragraph, bullets and a numbered list")
        return
    }
    #expect(heading == [MarkdownSpan("Result")])
    #expect(intro[1].link?.absoluteString == "https://example.com")
    #expect(bullets.map(\.blocks) == [paragraph("first item"), paragraph("second item")])
    #expect(numbered.map(\.blocks) == [paragraph("third item"), paragraph("fourth item")])
    #expect(blocks.last == .code(language: "swift", text: "let value = \"a long line\"\nprint(value)"))
}

@Test func keepsUnclosedFenceAsCodeWhileStreaming() {
    let first = "~~~swift\nline one\nline two"
    let expected: [MarkdownBlock] = [.code(language: "swift", text: "line one\nline two")]
    #expect(ChatMarkdown.parse(first) == expected)
    #expect(ChatMarkdown.parse(first + "\n~~~") == expected)
}

@Test func keepsInlineStylesAndLinksInNestedBlocks() {
    let blocks = ChatMarkdown.parse("""
    Use **bold**, *italic*, ~~struck~~ and `code`.

    - Visit [T3](https://t3.codes).
    """)
    guard case .paragraph(let intro) = blocks[0],
          case .list(nil, let items) = blocks[1],
          case .paragraph(let item) = items[0].blocks[0] else {
        Issue.record("Expected a paragraph and a list")
        return
    }
    #expect(intro.first(where: \.bold)?.text == "bold")
    #expect(intro.first(where: \.italic)?.text == "italic")
    #expect(intro.first(where: \.struck)?.text == "struck")
    #expect(intro.first(where: \.code)?.text == "code")
    #expect(item.first(where: { $0.link != nil })?.link?.absoluteString == "https://t3.codes")
}

@Test func parsesAlignedTableAndAnIncompleteStreamingRow() {
    let source = """
    | Left | Center | Right |
    | :--- | :---: | ---: |
    | **bold** | `code` | [T3](https://t3.codes) |
    | streaming
    """
    guard case .table(let table) = ChatMarkdown.parse(source).first else {
        Issue.record("Expected a GFM table")
        return
    }
    #expect(table.alignments == [.leading, .center, .trailing])
    #expect(table.rows[0].map { $0.map(\.text).joined() } == ["Left", "Center", "Right"])
    #expect(table.rows[1][0].first?.bold == true)
    #expect(table.rows[1][1].first?.code == true)
    #expect(table.rows[1][2].first?.link?.absoluteString == "https://t3.codes")
    #expect(table.rows[2] == [[MarkdownSpan("streaming")], [], []])
    let finished = ChatMarkdown.parse(source + " | finished | 3 |")
    guard case .table(let completedTable) = finished.first else {
        Issue.record("Expected the completed row to stay in the table")
        return
    }
    #expect(completedTable.rows.dropLast() == table.rows.dropLast())
}

@Test func preservesAllColumnsInAWideTable() {
    let columns = (1...20).map { "Detailed column \($0)" }
    func row(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
    let source = [row(columns), row(columns.map { _ in "---" }), row(columns.reversed())].joined(separator: "\n")
    guard case .table(let table) = ChatMarkdown.parse(source).first else {
        Issue.record("Expected a wide table")
        return
    }
    #expect(table.alignments.count == columns.count)
    #expect(table.rows[0].map { $0.map(\.text).joined() } == columns)
    #expect(table.rows[1].map { $0.map(\.text).joined() } == columns.reversed())
}

@Test func keepsTaskStatesAndNestedOrderedListsInsideQuote() {
    let blocks = ChatMarkdown.parse("""
    > Quoted
    >
    > - [x] done
    > - [ ] next
    >
    >   7. nested

    ---
    """)
    guard case .quote(let quote) = blocks[0],
          case .list(nil, let tasks) = quote[1],
          case .list(7, let nested) = tasks[1].blocks.last else {
        Issue.record("Expected a quote with nested tasks")
        return
    }
    #expect(quote[0] == .paragraph([MarkdownSpan("Quoted")]))
    #expect(tasks.map(\.checked) == [true, false])
    #expect(tasks[0].blocks == paragraph("done"))
    #expect(nested[0].blocks == paragraph("nested"))
    #expect(blocks.last == .rule)
}

@Test func providesWebAutolinksAndImageLinksAndDisplaysHTMLLiterally() {
    let blocks = ChatMarkdown.parse("""
    https://t3.codes, www.example.com, user@example.com, <https://example.org>, ![Image](https://example.org/logo.png)

    <details>
    <summary>Plain text</summary>
    $x^2$
    </details>
    """)
    guard case .paragraph(let spans) = blocks[0], case .paragraph(let details) = blocks[1] else {
        Issue.record("Expected links followed by literal HTML")
        return
    }
    #expect(spans.compactMap { $0.link?.absoluteString } == [
        "https://t3.codes", "http://www.example.com", "mailto:user@example.com",
        "https://example.org", "https://example.org/logo.png",
    ])
    #expect(spans.last?.text == "Image")
    #expect(details == [MarkdownSpan("""
    <details>
    <summary>Plain text</summary>
    $x^2$
    </details>
    """)])
}

@Test func keepsBareWebAutolinkQueriesAndBalancedParentheses() {
    let source = "Visit www.example.com?mode=demo, then (https://example.org/Reference_(API))."
    guard case .paragraph(let spans) = ChatMarkdown.parse(source).first else {
        Issue.record("Expected a paragraph with two bare autolinks")
        return
    }

    #expect(spans.map(\.text).joined() == source)
    #expect(spans.filter { $0.link != nil }.map(\.text) == [
        "www.example.com?mode=demo", "https://example.org/Reference_(API)",
    ])
    #expect(spans.compactMap { $0.link?.absoluteString } == [
        "http://www.example.com?mode=demo", "https://example.org/Reference_(API)",
    ])
}

private func paragraph(_ text: String) -> [MarkdownBlock] { [.paragraph([MarkdownSpan(text)])] }
