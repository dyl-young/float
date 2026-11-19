import AppKit
import SwiftUI

/// Colours from the nordbones T3 theme.
enum Theme {
    static let canvas = colour(0.059, 0.098, 0.122, light: 0xECEFF4)
    static let surface = colour(0.069, 0.111, 0.147, light: 0xE5E9F0)
    static let raised = colour(0.100, 0.143, 0.181, light: 0xF5F7FA)
    static let overlay = colour(0.100, 0.143, 0.181, light: 0xFFFFFF)
    static let tray = colour(0.064, 0.104, 0.134, light: 0xECEFF4)
    static let border = colour(0.180, 0.255, 0.321, light: 0xD8DEE9)
    static let hairline = colour(0.63, 0.76, 0.86, light: 0x2E3440, darkOpacity: 0.13, lightOpacity: 0.16)
    static let selection = colour(28.0 / 255.0, 51.0 / 255.0, 73.0 / 255.0, light: 0xCFD8E6)
    static let text = Color(nsColor: textColor)
    static let muted = colour(0.493, 0.544, 0.584, light: 0x4C566A)
    static let placeholder = colour(0.501, 0.554, 0.600, light: 0x7B8394)
    static let searchPlaceholder = Color(nsColor: srgb(0x616E88))
    static let accent = Color(nsColor: accentColor)
    static let accentInk = Color(nsColor: accentInkColor)
    static let accentForeground = canvas
    static let message = colour(0.118, 0.259, 0.372, light: 0xD8E2EE)
    static let code = colour(0.095, 0.128, 0.158, light: 0xE5E9F0)
    static let codeBlock = colour(0.180, 0.255, 0.321, light: 0xE5E9F0, darkOpacity: 0.32)
    static let error = colour(0.984, 0.255, 0.290, light: 0xC42B3A)
    static let errorSurface = colour(0.984, 0.255, 0.290, light: 0xF4E1E3, darkOpacity: 0.10)
    static let warning = colour(0.996, 0.604, 0.0, light: 0xD08770)
    static let warningInk = colour(0.996, 0.604, 0.0, light: 0x9A5B3C)
    static let warningSurface = colour(0.209, 0.179, 0.102, light: 0xF6EBDD)
    static let warningNotice = colour(0.996, 0.604, 0.0, light: 0xF6EBDD, darkOpacity: 0.10)
    static let accentNotice = colour(0.424, 0.690, 0.914, light: 0xDCE6F0, darkOpacity: 0.10)
    static let success = colour(0.36, 0.78, 0.56, light: 0x287655)
    static let attachmentFill = colour(1, 1, 1, light: 0x2E3440, darkOpacity: 0.06, lightOpacity: 0.06)

    static let textColor = adaptive(dark: srgb(0.882, 0.945, 1.0), light: srgb(0x2E3440))
    static let accentColor = adaptive(dark: srgb(0.424, 0.690, 0.914), light: srgb(0x5E81AC))
    static let accentInkColor = adaptive(dark: srgb(0.424, 0.690, 0.914), light: srgb(0x406188))
    static let skillFillColor = adaptive(dark: srgb(0.424, 0.690, 0.914, opacity: 0.16), light: srgb(0xDCE6F0))
    static let claude = adaptive(dark: srgb(0xD97757), light: srgb(0xB85A3E))
    static let cursor = adaptive(dark: srgb(0xEDECEC), light: srgb(0x2E3440))
    static let openCode = adaptive(dark: srgb(0.945, 0.925, 0.925), light: srgb(0x2E3440))
    static let openCodeInset = adaptive(dark: srgb(0.294, 0.275, 0.275), light: srgb(0xAEB7C6))

    static let radius: CGFloat = 16

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in isDark(appearance) ? dark : light }
    }

    static func srgb(_ hex: UInt32, opacity: CGFloat = 1) -> NSColor {
        srgb(CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255,
             CGFloat(hex & 0xFF) / 255, opacity: opacity)
    }

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, opacity: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: opacity)
    }

    private static func colour(
        _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, light: UInt32, darkOpacity: CGFloat = 1, lightOpacity: CGFloat = 1
    ) -> Color {
        Color(nsColor: adaptive(dark: srgb(r, g, b, opacity: darkOpacity), light: srgb(light, opacity: lightOpacity)))
    }
}
