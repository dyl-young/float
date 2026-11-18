import Foundation
import Testing
@testable import FloatCore

@MainActor
struct PanelSizingTests {
    @Test func persistsAcrossInstancesAndScreenLimits() throws {
        let domain = "float-panel-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        PanelSizing(defaults: defaults).save(CGSize(width: 640, height: 710))
        let reopened = PanelSizing(defaults: try #require(UserDefaults(suiteName: domain)))
        #expect(reopened.width == 640)
        #expect(reopened.height(on: 800) == 680)
        #expect(reopened.height(on: 1000) == 710)
    }

    @Test func migratesLegacySizeAndKeepsReset() throws {
        let domain = "float-panel-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }

        defaults.set(610.0, forKey: "panelMaximumHeight")
        let legacy = ["panelWidth": 660.0, "panelMaximumHeight": 730.0]
        let sizing = PanelSizing(defaults: defaults, legacy: legacy)
        #expect(sizing.width == 660)
        #expect(sizing.height(on: 1000) == 610)
        sizing.reset()
        let reopened = PanelSizing(defaults: defaults, legacy: legacy)
        #expect(Double(reopened.width) == PanelWidthLimits.defaultWidth)
        #expect(Double(reopened.height(on: 1000)) == PanelHeightLimits.defaultMaximum)
    }
}
