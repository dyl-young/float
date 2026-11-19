import AppKit
import FloatCore
import SwiftUI

extension T3ProjectIconColor {
    /// Tailwind’s -400 dark and -600 light shades.
    var themeColor: Color {
        let components: (Double, Double, Double) = switch self {
        case .gray: (0.6057, 0.6304, 0.6802)
        case .red: (0.9335, 0.4317, 0.4235)
        case .orange: (0.9502, 0.5618, 0.2110)
        case .amber: (0.9592, 0.7385, 0.1183)
        case .yellow: (0.9599, 0.7902, 0.0585)
        case .lime: (0.6687, 0.8938, 0.2088)
        case .green: (0.3995, 0.8623, 0.4932)
        case .emerald: (0.3347, 0.8196, 0.5916)
        case .teal: (0.3228, 0.8221, 0.7444)
        case .cyan: (0.2946, 0.8140, 0.9350)
        case .sky: (0.3060, 0.7250, 0.9802)
        case .blue: (0.3974, 0.6281, 0.9921)
        case .indigo: (0.4950, 0.5253, 0.9851)
        case .violet: (0.6312, 0.5222, 0.9900)
        case .purple: (0.7199, 0.4925, 0.9952)
        case .fuchsia: (0.8668, 0.4478, 0.9790)
        case .pink: (0.9155, 0.4305, 0.7027)
        case .rose: (0.9429, 0.4308, 0.5031)
        }
        let light: UInt32 = switch self {
        case .gray: 0x4A5565
        case .red: 0xE7000B
        case .orange: 0xF54900
        case .amber: 0xE17100
        case .yellow: 0xD08700
        case .lime: 0x5EA500
        case .green: 0x00A63E
        case .emerald: 0x009966
        case .teal: 0x009689
        case .cyan: 0x0092B8
        case .sky: 0x0084D1
        case .blue: 0x155DFC
        case .indigo: 0x4F39F6
        case .violet: 0x7F22FE
        case .purple: 0x9810FA
        case .fuchsia: 0xC800DE
        case .pink: 0xE60076
        case .rose: 0xEC003F
        }
        let dark = NSColor(displayP3Red: components.0, green: components.1, blue: components.2, alpha: 1)
        return Color(nsColor: Theme.adaptive(dark: dark, light: Theme.srgb(light)))
    }
}
