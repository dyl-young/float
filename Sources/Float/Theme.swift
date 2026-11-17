import SwiftUI

/// Colours from the nordbones T3 theme (converted from its OKLCH values).
enum Theme {
    static let canvas = Color(red: 0.059, green: 0.098, blue: 0.122)
    static let surface = Color(red: 0.069, green: 0.111, blue: 0.147)
    static let raised = Color(red: 0.100, green: 0.143, blue: 0.181)
    static let tray = Color(red: 0.064, green: 0.104, blue: 0.134)
    static let border = Color(red: 0.180, green: 0.255, blue: 0.321)
    static let hairline = Color(red: 0.63, green: 0.76, blue: 0.86).opacity(0.13)
    static let text = Color(red: 0.882, green: 0.945, blue: 1.0)
    static let muted = Color(red: 0.493, green: 0.544, blue: 0.584)
    static let placeholder = Color(red: 0.501, green: 0.554, blue: 0.600)
    static let accent = Color(red: 0.424, green: 0.690, blue: 0.914)
    static let message = Color(red: 0.118, green: 0.259, blue: 0.372)
    static let code = Color(red: 0.095, green: 0.128, blue: 0.158)
    static let error = Color(red: 0.984, green: 0.255, blue: 0.290)
    static let warning = Color(red: 0.996, green: 0.604, blue: 0.0)
    static let warningSurface = Color(red: 0.209, green: 0.179, blue: 0.102)
    static let success = Color(red: 0.36, green: 0.78, blue: 0.56)
    static let claude = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
    static let cursor = Color(red: 237.0 / 255.0, green: 236.0 / 255.0, blue: 236.0 / 255.0)
    static let openCode = Color(red: 0.945, green: 0.925, blue: 0.925)
    static let openCodeInset = Color(red: 0.294, green: 0.275, blue: 0.275)

    static let radius: CGFloat = 16
}
