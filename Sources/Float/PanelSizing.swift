import FloatCore
import Foundation
import SwiftUI

@MainActor
final class PanelSizing: ObservableObject {
    private static let maximumKey = "panelMaximumHeight"

    @Published private(set) var preferredMaximum: CGFloat
    @Published private(set) var visibleScreenHeight: CGFloat
    private let defaults: UserDefaults
    private var dragStart: CGFloat?

    var maximumHeight: CGFloat {
        CGFloat(PanelHeightLimits.clamp(
            Double(preferredMaximum),
            visibleScreenHeight: Double(visibleScreenHeight)
        ))
    }

    var isDragging: Bool { dragStart != nil }

    init(defaults: UserDefaults = .standard, visibleScreenHeight: CGFloat = 1_000) {
        self.defaults = defaults
        self.visibleScreenHeight = visibleScreenHeight
        preferredMaximum = defaults.object(forKey: Self.maximumKey) == nil
            ? CGFloat(PanelHeightLimits.defaultMaximum)
            : CGFloat(defaults.double(forKey: Self.maximumKey))
    }

    func updateVisibleScreenHeight(_ height: CGFloat) {
        guard height > 0, height != visibleScreenHeight else { return }
        visibleScreenHeight = height
    }

    func beginResize() {
        dragStart = maximumHeight
    }

    func resize(by delta: CGFloat) {
        guard let dragStart else { return }
        preferredMaximum = CGFloat(PanelHeightLimits.clamp(
            Double(dragStart + delta),
            visibleScreenHeight: Double(visibleScreenHeight)
        ))
    }

    func endResize() {
        guard dragStart != nil else { return }
        dragStart = nil
        defaults.set(Double(preferredMaximum), forKey: Self.maximumKey)
    }

    func reset() {
        dragStart = nil
        preferredMaximum = CGFloat(PanelHeightLimits.defaultMaximum)
        defaults.set(PanelHeightLimits.defaultMaximum, forKey: Self.maximumKey)
    }
}
