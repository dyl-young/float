import SwiftUI

/// The nordbones "thinking" pixel loader: a 3×3 grid with dim cells at 35% and
/// four frames of lit cells, stepping every 300 ms.
struct ThinkingLoader: View {
    var size: CGFloat = 14
    var color: Color = Theme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Row-major cell indices (0...8) lit in each frame, from the theme's mask strip.
    private static let frames: [Set<Int>] = [
        [0, 2, 4, 5, 7],
        [2, 3, 5, 7, 8],
        [0, 4, 5, 6, 7],
        [1, 5, 6, 7, 8],
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let frame = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 4
            grid(lit: Self.frames[frame])
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Thinking")
    }

    private func grid(lit: Set<Int>) -> some View {
        Canvas { context, canvas in
            let unit = canvas.width / 16
            for index in 0..<9 {
                let rect = CGRect(
                    x: (1 + CGFloat(index % 3) * 5) * unit, y: (1 + CGFloat(index / 3) * 5) * unit,
                    width: 4 * unit, height: 4 * unit
                )
                context.fill(Path(rect), with: .color(color.opacity(lit.contains(index) ? 1 : 0.35)))
            }
        }
    }
}
