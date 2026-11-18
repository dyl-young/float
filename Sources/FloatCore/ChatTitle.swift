import Foundation

public enum ChatTitle {
    public static func plainText(_ title: String) -> String {
        // Strip ATX heading delimiters before parsing inline Markdown. Inline
        // parsing keeps literal punctuation such as issue numbers and file names.
        let withoutHeadingMarkers = title.replacingOccurrences(
            of: #"(?m)^[ \t]{0,3}#{1,6}(?:[ \t]+|$)(.*?)(?:[ \t]+#+[ \t]*)?$"#,
            with: "$1", options: .regularExpression
        )
        let parsed = try? AttributedString(
            markdown: withoutHeadingMarkers,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return parsed.map { String($0.characters) } ?? withoutHeadingMarkers
    }
}
