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

struct ThinkingActivity: View {
    let startedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date.now

    private static let duration = 2.2
    private static let steps = 30
    private static let bandWidth: CGFloat = 72
    // T3 live-activity-focus, with the rem stops converted to points.
    private static let band = LinearGradient(stops: [
        .init(color: .clear, location: 0),
        .init(color: Theme.text.opacity(0.12), location: 10.8 / bandWidth),
        .init(color: Theme.text.opacity(0.55), location: 25.2 / bandWidth),
        .init(color: Theme.text, location: 36 / bandWidth),
        .init(color: Theme.text.opacity(0.55), location: 46.8 / bandWidth),
        .init(color: Theme.text.opacity(0.12), location: 61.2 / bandWidth),
        .init(color: .clear, location: 1),
    ], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        let start = startedAt ?? appearedAt
        let step = Self.duration / Double(Self.steps)
        TimelineView(.periodic(from: start, by: reduceMotion ? 1 : step)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let progress = CGFloat(Int(elapsed / step) % Self.steps) / CGFloat(Self.steps)
            HStack(spacing: 6) {
                ThinkingLoader(size: 16)
                    .accessibilityHidden(true)
                Text("Thinking")
                    .foregroundStyle(Theme.muted)
                    .overlay {
                        if !reduceMotion {
                            Text("Thinking")
                                .foregroundStyle(Theme.text)
                                .mask(alignment: .leading) {
                                    GeometryReader { geometry in
                                        Self.band
                                            .frame(width: Self.bandWidth)
                                            .offset(x: -Self.bandWidth + progress * (geometry.size.width + 2 * Self.bandWidth))
                                    }
                                }
                                .accessibilityHidden(true)
                        }
                    }
                Text("· \(Int(elapsed))s")
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            .accessibilityElement(children: .combine)
        }
    }
}
