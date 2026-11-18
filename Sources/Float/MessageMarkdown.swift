import AppKit
import FloatCore
import SwiftUI

struct MessageMarkdown: View {
    let source: String
    var isUser = false

    @State private var lastBlocks: [MarkdownBlock] = []

    var body: some View {
        let isLong = source.utf8.count > 24_000
        let blocks = isLong ? lastBlocks : Self.cache.blocks(source, isUser: isUser)
        MarkdownBlocks(blocks: blocks, isUser: isUser)
            .tint(Theme.accent)
            .task(id: source) {
                if isLong {
                    let source = source
                    let isUser = isUser
                    let blocks = await Task.detached(priority: .userInitiated) {
                        Self.cache.blocks(source, isUser: isUser)
                    }.value
                    guard !Task.isCancelled else { return }
                    lastBlocks = blocks
                } else if source.utf8.count > 20_000 {
                    lastBlocks = blocks
                }
            }
    }

    nonisolated private static let cache = MarkdownCache()
}

// NSCache supports concurrent reads and writes. Values are immutable, so the
// timeline and the frosted composer can share them across background parses.
private final class MarkdownCache: @unchecked Sendable {
    private final class Parsed {
        let blocks: [MarkdownBlock]
        init(_ blocks: [MarkdownBlock]) { self.blocks = blocks }
    }

    private let cache = NSCache<NSString, Parsed>()

    init() {
        cache.countLimit = 128
        cache.totalCostLimit = 1_000_000
    }

    func blocks(_ source: String, isUser: Bool) -> [MarkdownBlock] {
        let key = (isUser ? "+" + source : "-" + source) as NSString
        if let parsed = cache.object(forKey: key) { return parsed.blocks }
        let blocks = ChatMarkdown.parse(source, preserveLineBreaks: isUser)
        cache.setObject(Parsed(blocks), forKey: key, cost: key.length)
        return blocks
    }
}

private struct MarkdownBlocks: View {
    let blocks: [MarkdownBlock]
    let isUser: Bool
    var bulletDepth = 0
    var orderedDepth = 0

    private static let bodySize: CGFloat = 13.5
    // T3's 15px prose scales to 13.5pt. Its 16px rem therefore scales to 14.4pt.
    private static let rem: CGFloat = 14.4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                render(blocks[index])
                    .padding(.top, index == 0 ? 0 : spacing(before: blocks[index]))
            }
        }
    }

    private func spacing(before block: MarkdownBlock) -> CGFloat {
        if case .heading = block { return 1.25 * Self.rem }
        return 0.65 * Self.rem
    }

    @ViewBuilder private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let spans):
            MarkdownText(spans: spans, size: Self.bodySize)
        case .heading(let level, let spans):
            let size = [1.25, 1.125, 1, 0.875, 0.875, 0.875][level - 1] * Self.rem
            MarkdownText(spans: spans, size: min(14, size), weight: .semibold,
                         color: level == 6 ? Theme.muted : Theme.text)
                .accessibilityAddTraits(.isHeader)
        case .list(let start, let items):
            list(start: start, items: items)
        case .quote(let blocks):
            MarkdownBlocks(blocks: blocks, isUser: isUser, bulletDepth: bulletDepth, orderedDepth: orderedDepth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 0.8 * Self.rem + 1.8)
                .background(alignment: .leading) {
                    Rectangle().fill(Theme.text.opacity(0.35)).frame(width: 1.8)
                }
        case .rule:
            Rectangle().fill(Theme.muted).frame(height: 1)
                .accessibilityHidden(true)
        case .table(let table):
            MarkdownTableView(table: table)
        case .code(let language, let text):
            MarkdownCodeBlock(language: language, text: text)
        }
    }

    private func list(start: UInt?, items: [MarkdownListItem]) -> some View {
        let markers = items.indices.map { marker(start: start, offset: $0) }
        let font = NSFont.monospacedDigitSystemFont(ofSize: Self.bodySize, weight: .regular)
        let markerWidth = markers.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let gutter = max(1.25 * Self.rem, markerWidth + 5)
        return VStack(alignment: .leading, spacing: 0.25 * Self.rem) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Group {
                        if let checked = items[index].checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .accessibilityLabel(checked ? "Checked" : "Unchecked")
                        } else {
                            Text(markers[index])
                                .font(.system(size: Self.bodySize).monospacedDigit())
                        }
                    }
                    .foregroundStyle(Theme.text)
                    .frame(width: gutter - 5, alignment: .trailing)
                    MarkdownBlocks(blocks: items[index].blocks, isUser: isUser,
                                   bulletDepth: bulletDepth + (start == nil ? 1 : 0),
                                   orderedDepth: orderedDepth + (start == nil ? 0 : 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func marker(start: UInt?, offset: Int) -> String {
        guard let start else { return ["•", "◦", "▪"][min(2, bulletDepth)] }
        let number = start + UInt(offset)
        if !isUser, orderedDepth > 0, number > 0 {
            if orderedDepth == 1 {
                var remaining = number
                var letters = ""
                while remaining > 0 {
                    remaining -= 1
                    letters = String(UnicodeScalar(97 + UInt32(remaining % 26))!) + letters
                    remaining /= 26
                }
                return letters + "."
            }
            if number <= 3999 {
                var remaining = number
                var roman = ""
                let symbols: [(UInt, String)] = [
                    (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"),
                    (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"),
                    (5, "v"), (4, "iv"), (1, "i"),
                ]
                for (value, symbol) in symbols {
                    roman += String(repeating: symbol, count: Int(remaining / value))
                    remaining %= value
                }
                return roman + "."
            }
        }
        return "\(number)."
    }
}

private struct MarkdownText: View {
    let spans: [MarkdownSpan]
    let size: CGFloat
    var weight: Font.Weight = .regular
    var color = Theme.text

    var body: some View {
        Text(attributed)
            .foregroundStyle(color)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var text = AttributedString()
        for span in spans {
            var run = AttributedString(span.text)
            let font = span.code
                ? Font.system(size: max(10.5, size * 0.85), weight: weight, design: .monospaced)
                : Font.system(size: size, weight: weight)
            var styled = span.bold ? font.bold() : font
            if span.italic { styled = styled.italic() }
            run.font = styled
            if span.code { run.backgroundColor = Theme.text.opacity(0.10) }
            if span.struck { run.strikethroughStyle = .single }
            if let link = span.link {
                run.link = link
                run.foregroundColor = Theme.accent
            }
            text += run
        }
        return text
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow(alignment: .top) {
                        ForEach(table.alignments.indices, id: \.self) { column in
                            cell(row: row, column: column)
                        }
                    }
                    Rectangle()
                        .fill(Theme.border.opacity(0.60))
                        .frame(height: 0.9)
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
            .frame(minWidth: viewportWidth, alignment: .leading)
            .background(OverlayScrollers())
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { viewportWidth = $0 }
        .flashScrollKnobsOnHover()
    }

    private func cell(row: Int, column: Int) -> some View {
        let alignment = table.alignments[column]
        let spans = table.rows[row]
        return CappedCellWidth {
            MarkdownText(spans: spans.indices.contains(column) ? spans[column] : [],
                         size: 12.6, weight: row == 0 ? .semibold : .regular)
                .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
        .padding(.leading, column == 0 ? 0 : 10.8)
        .padding(.trailing, column == table.alignments.count - 1 ? 0 : 10.8)
        .padding(.vertical, row == 0 ? 7.92 : 6.48)
    }
}

/// Let every column keep its natural width up to T3's 24rem cell cap.
private struct CappedCellWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cell = subviews[0]
        let width = min(cell.sizeThatFits(.unspecified).width, proposal.width ?? .infinity, 24 * 14.4)
        return cell.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
