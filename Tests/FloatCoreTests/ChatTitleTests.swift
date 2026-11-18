import Testing
import FloatCore

@Test(arguments: [
    ("Run `echo float-approval-test` using Bash.", "Run echo float-approval-test using Bash."),
    ("## **Review** _Float_ ~~draft~~ ###", "Review Float draft"),
    ("See [the **guide**](https://example.com/a_(b))", "See the guide"),
    ("### Fix `foo_bar` in [Float](https://example.com)", "Fix foo_bar in Float"),
    ("Fix issue #123 in C# and foo_bar", "Fix issue #123 in C# and foo_bar"),
    (#"Keep \*literal\* and ``a`b``"#, "Keep *literal* and a`b"),
    ("", ""),
])
func stripsInlineMarkdownFromChatTitles(source: String, expected: String) {
    #expect(ChatTitle.plainText(source) == expected)
}
