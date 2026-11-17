import Testing
@testable import FloatCore

@Test func panelHeightUsesRequestedValueWithinLimits() {
    #expect(PanelHeightLimits.clamp(560, visibleScreenHeight: 1_000) == 560)
}

@Test func panelHeightHasMinimum() {
    #expect(PanelHeightLimits.clamp(120, visibleScreenHeight: 1_000) == 240)
}

@Test func panelHeightUsesEightyFivePercentScreenMaximum() {
    #expect(PanelHeightLimits.clamp(900, visibleScreenHeight: 1_000) == 850)
}

@Test func panelHeightFallsBackToDefaultForInvalidStoredValue() {
    #expect(PanelHeightLimits.clamp(.nan, visibleScreenHeight: 1_000) == 560)
}
