import FloatCore
import Foundation

@MainActor
final class PanelSizing {
    // Keep reading the previous maximum-height preference as the fixed tray height.
    private static let heightKey = "panelMaximumHeight"
    private static let widthKey = "panelWidth"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var width: CGFloat {
        CGFloat(PanelWidthLimits.clamp(defaults.object(forKey: Self.widthKey) as? Double ?? PanelWidthLimits.defaultWidth))
    }

    func height(on screen: CGFloat) -> CGFloat {
        let saved = defaults.object(forKey: Self.heightKey) as? Double ?? PanelHeightLimits.defaultMaximum
        return clampHeight(saved, on: screen)
    }

    func clampHeight(_ height: Double, on screen: CGFloat) -> CGFloat {
        CGFloat(PanelHeightLimits.clamp(height, visibleScreenHeight: Double(screen)))
    }

    func save(_ size: CGSize) {
        defaults.set(Double(size.height), forKey: Self.heightKey)
        defaults.set(Double(size.width), forKey: Self.widthKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.heightKey)
        defaults.removeObject(forKey: Self.widthKey)
    }
}
