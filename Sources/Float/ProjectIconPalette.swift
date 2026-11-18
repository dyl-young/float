import FloatCore
import SwiftUI

extension T3ProjectIconColor {
    /// Tailwind’s dark-mode -400 palette, converted from OKLCH to Display P3.
    var darkColor: Color {
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
        return Color(.displayP3, red: components.0, green: components.1, blue: components.2)
    }
}
