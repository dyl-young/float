import AppKit
import SwiftUI

/// A solid tray that tucks `radius` under the frosted input, with concave corners
/// where it meets the input. `.top` is the message tray above the input, `.bottom`
/// is the controls footer below it. The outer corners come from the shell's clip.
struct TrayShape: Shape {
    enum Side { case top, bottom }
    let side: Side
    var radius: CGFloat = Theme.radius

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        switch side {
        case .bottom:
            // Ears rise to the top edge at the far left and right.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY + r),
                        tangent2End: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r)
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + r))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY + r),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .top:
            // Ears drop to the bottom edge at the far left and right.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY - r),
                        tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY - r))
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY - r),
                        tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        }
        path.closeSubpath()
        return path
    }
}

/// The external-link mark from Float's design, drawn on its original 24-unit grid.
struct OpenInT3Shape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let origin = CGPoint(
            x: rect.midX - 12 * scale,
            y: rect.midY - 12 * scale
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()
        path.move(to: point(15, 3))
        path.addLine(to: point(21, 3))
        path.addLine(to: point(21, 9))

        path.move(to: point(10, 14))
        path.addLine(to: point(21, 3))

        path.move(to: point(18, 13))
        path.addLine(to: point(18, 19))
        path.addArc(
            tangent1End: point(18, 21), tangent2End: point(16, 21), radius: 2 * scale
        )
        path.addLine(to: point(5, 21))
        path.addArc(
            tangent1End: point(3, 21), tangent2End: point(3, 19), radius: 2 * scale
        )
        path.addLine(to: point(3, 8))
        path.addArc(
            tangent1End: point(3, 6), tangent2End: point(5, 6), radius: 2 * scale
        )
        path.addLine(to: point(11, 6))
        return path
    }
}

/// The Float cloud, drawn on a 24-unit grid (bounds roughly x 4–21.5, y 6–18).
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Fit the cloud's own box (x 2.75–22.75, y 2–22) into rect.
        let scale = min(rect.width, rect.height) / 20
        let ox = rect.midX - 12.75 * scale, oy = rect.midY - 12 * scale
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
        var path = Path()
        path.move(to: p(7.5, 18))
        path.addArc(center: p(7.5, 14.5), radius: 3.5 * scale, startAngle: .degrees(90), endAngle: .degrees(262.3), clockwise: false)
        path.addArc(center: p(12, 10.5), radius: 5 * scale, startAngle: .degrees(173.9), endAngle: .degrees(342.7), clockwise: false)
        path.addArc(center: p(17, 13.5), radius: 4.5 * scale, startAngle: .degrees(267.1), endAngle: .degrees(90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

extension NSImage {
    /// Template menu bar glyph of the Float cloud outline.
    static func floatCloud(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let path = CloudShape().path(in: rect.insetBy(dx: 1, dy: 1))
            let bezier = NSBezierPath(cgPath: path.cgPath)
            bezier.lineWidth = 1.6
            bezier.lineJoinStyle = .round
            NSColor.black.setStroke()
            bezier.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Float"
        return image
    }
}
