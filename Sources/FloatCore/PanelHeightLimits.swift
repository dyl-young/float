public enum PanelHeightLimits {
    public static let defaultMaximum = 560.0
    public static let minimum = 240.0
    public static let screenFraction = 0.85

    public static func clamp(_ height: Double, visibleScreenHeight: Double) -> Double {
        let requested = height.isFinite ? height : defaultMaximum
        let screenMaximum = max(0, visibleScreenHeight * screenFraction)
        return min(max(requested, minimum), screenMaximum)
    }
}

public enum PanelWidthLimits {
    public static let defaultWidth = 516.0

    public static func clamp(_ width: Double) -> Double {
        min(900, max(420, width.isFinite ? width : defaultWidth))
    }
}
