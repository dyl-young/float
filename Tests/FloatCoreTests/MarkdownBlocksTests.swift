import Testing
@testable import FloatCore

@Test func parsesMarkdownBlocks() {
    let blocks = MarkdownBlockParser.parse("""
    # Result

    Intro with [a link](https://example.com).

    - first item
    * second item

    3. third item
    4) fourth item

    ```swift
    let value = "a long line"
    print(value)
    ```
    """)

    #expect(blocks == [
        .heading("Result"),
        .paragraph("Intro with [a link](https://example.com)."),
        .unorderedList(["first item", "second item"]),
        .orderedList([
            MarkdownOrderedItem(number: 3, text: "third item"),
            MarkdownOrderedItem(number: 4, text: "fourth item"),
        ]),
        .code(language: "swift", text: "let value = \"a long line\"\nprint(value)"),
    ])
}

@Test func keepsUnclosedFenceAsCode() {
    #expect(MarkdownBlockParser.parse("```\nline one\nline two") == [
        .code(language: nil, text: "line one\nline two"),
    ])
}

@Test func leavesInlineMarkdownInParagraphsAndListItems() {
    #expect(MarkdownBlockParser.parse("Use **bold** and `code`.\n\n- Visit [T3](https://t3.codes).") == [
        .paragraph("Use **bold** and `code`."),
        .unorderedList(["Visit [T3](https://t3.codes)."]),
    ])
}
