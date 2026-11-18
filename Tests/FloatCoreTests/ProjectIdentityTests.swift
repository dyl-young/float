import Foundation
import Testing

@testable import FloatCore

@Test func projectIdentityMatchesT3Palette() {
    #expect(T3ProjectIdentity.derive(from: "flow-reports") == .init(monogram: "FR", color: .purple))
    #expect(T3ProjectIdentity.derive(from: "float") == .init(monogram: "FT", color: .green))
    #expect(T3ProjectIdentity.derive(from: "t3code") == .init(monogram: "T3", color: .teal))
}

@Test func projectIdentityUsesJavaScriptNormalizationAndCodePoints() {
    #expect(T3ProjectIdentity.derive(from: "\u{FEFF} ＦＬＯＷ-reports\n").color == .purple)
    #expect(T3ProjectIdentity.derive(from: "Straße report").monogram == "SR")
    #expect(T3ProjectIdentity.derive(from: "ßeta").monogram == "SS")
    #expect(T3ProjectIdentity.derive(from: "a² second word").monogram == "A2")
    #expect(T3ProjectIdentity.derive(from: "first middle last").monogram == "FL")
    #expect(T3ProjectIdentity.derive(from: "🔧").monogram == "PR")
    #expect(T3ProjectIdentity.derive(from: "𐐨x").monogram == "𐐀X")
    #expect(T3ProjectIdentity.derive(from: " \n").color == T3ProjectIdentity.derive(from: "project").color)
}

@Test func projectIconDecodesLucideNameAndColor() throws {
    let data = Data(#"{"kind":"lucide","name":"rocket","color":"violet"}"#.utf8)
    let icon = try JSONDecoder().decode(T3ProjectIcon.self, from: data)
    #expect(icon.kind == "lucide")
    #expect(icon.name == "rocket")
    #expect(icon.color == "violet")

    let legacy = try JSONDecoder().decode(T3ProjectIcon.self, from: Data(#"{"kind":"emoji","emoji":"🚀"}"#.utf8))
    #expect(legacy.emoji == "🚀")
    #expect(legacy.color == nil)
    #expect(legacy.name == nil)
}
