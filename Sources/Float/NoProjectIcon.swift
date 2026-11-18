import SwiftUI

/// Lucide's `message-square-dashed`, which T3 uses for chats with no project.
/// Drawn from lucide's 24-unit paths so it matches T3 at any size.
struct NoProjectIcon: View {
    var size: CGFloat = 12

    var body: some View {
        MessageSquareDashed()
            .stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct MessageSquareDashed: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Dots along the dashed edges ("h.01" with round caps).
        for (x, y) in [(12.0, 19.0), (12, 3), (16, 19), (16, 3), (2, 13), (2, 9), (22, 13), (22, 9), (8, 3)] {
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + 0.01, y: y))
        }
        // Rounded corners.
        path.move(to: CGPoint(x: 2, y: 5))
        path.addArc(tangent1End: CGPoint(x: 2, y: 3), tangent2End: CGPoint(x: 4, y: 3), radius: 2)
        path.move(to: CGPoint(x: 20, y: 3))
        path.addArc(tangent1End: CGPoint(x: 22, y: 3), tangent2End: CGPoint(x: 22, y: 5), radius: 2)
        path.move(to: CGPoint(x: 22, y: 17))
        path.addArc(tangent1End: CGPoint(x: 22, y: 19), tangent2End: CGPoint(x: 20, y: 19), radius: 2)
        // The tail: M2 17v4.286a.71.71 0 0 0 1.212.502l2.202-2.202A2 2 0 0 1 6.828 19H8
        path.move(to: CGPoint(x: 2, y: 17))
        path.addLine(to: CGPoint(x: 2, y: 21.286))
        path.addQuadCurve(to: CGPoint(x: 3.212, y: 21.788), control: CGPoint(x: 2, y: 22.1))
        path.addLine(to: CGPoint(x: 5.414, y: 19.586))
        path.addQuadCurve(to: CGPoint(x: 6.828, y: 19), control: CGPoint(x: 6, y: 19))
        path.addLine(to: CGPoint(x: 8, y: 19))
        let scale = min(rect.width, rect.height) / 24
        return path.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        )
    }
}
