import AppKit
import FloatCore

@MainActor
enum SkillChip {
    static func image(for chip: ComposerSkillChip, appearance: NSAppearance? = nil) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let label = chip.label as NSString
        let labelWidth = min(254, ceil(label.size(withAttributes: [.font: font]).width))
        let image = NSImage(size: NSSize(width: labelWidth + 29, height: 20), flipped: true) { rect in
            let draw = {
                Theme.skillFillColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
                let accent = Theme.accentInkColor
                let icon = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 10.5, weight: .medium)
                        .applying(.init(paletteColors: [accent])))
                icon?.draw(in: NSRect(x: 7, y: 4.5, width: 11, height: 11))
                label.draw(with: NSRect(x: 22, y: 2.5, width: labelWidth + 1, height: 16),
                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                           attributes: [.font: font, .foregroundColor: accent])
            }
            if let appearance {
                appearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        image.cacheMode = .never
        image.accessibilityDescription = chip.label
        return image
    }
}

final class SkillChipAttachment: NSTextAttachment {
    let chip: ComposerSkillChip

    @MainActor init(chip: ComposerSkillChip) {
        self.chip = chip
        super.init(data: nil, ofType: nil)
        let glyph = SkillChip.image(for: chip)
        image = glyph
        bounds = NSRect(x: 0, y: -4, width: glyph.size.width, height: glyph.size.height)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
