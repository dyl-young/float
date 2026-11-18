import Foundation

@MainActor
public final class PanelSizing {
    // Keep reading the previous maximum-height preference as the fixed tray height.
    private static let heightKey = "panelMaximumHeight"
    private static let widthKey = "panelWidth"
    private let defaults: UserDefaults

    // swift run has no bundle identifier and uses a different standard domain.
    public static let defaultsDomain = "com.dylyoung.float"

    public convenience init() {
        let defaults = UserDefaults(suiteName: Self.defaultsDomain) ?? .standard
        self.init(defaults: defaults, legacy: defaults.persistentDomain(forName: "Float") ?? [:])
    }

    public init(defaults: UserDefaults, legacy: [String: Any] = [:]) {
        self.defaults = defaults
        for key in [Self.heightKey, Self.widthKey] where defaults.object(forKey: key) == nil {
            if let value = legacy[key] as? Double { defaults.set(value, forKey: key) }
        }
    }

    public var width: CGFloat {
        CGFloat(PanelWidthLimits.clamp(defaults.object(forKey: Self.widthKey) as? Double ?? PanelWidthLimits.defaultWidth))
    }

    public func height(on screen: CGFloat) -> CGFloat {
        let saved = defaults.object(forKey: Self.heightKey) as? Double ?? PanelHeightLimits.defaultMaximum
        return clampHeight(saved, on: screen)
    }

    public func clampHeight(_ height: Double, on screen: CGFloat) -> CGFloat {
        CGFloat(PanelHeightLimits.clamp(height, visibleScreenHeight: Double(screen)))
    }

    public func save(_ size: CGSize) {
        defaults.set(Double(size.height), forKey: Self.heightKey)
        defaults.set(Double(size.width), forKey: Self.widthKey)
    }

    public func reset() {
        // Store the defaults so resetting cannot revive an older CLI preference.
        save(CGSize(width: PanelWidthLimits.defaultWidth, height: PanelHeightLimits.defaultMaximum))
    }
}
