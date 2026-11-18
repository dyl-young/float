import Foundation

// The declaration order is the palette order used by T3's projectIdentity.ts.
public enum T3ProjectIconColor: String, CaseIterable, Sendable {
    case gray, red, orange, amber, yellow, lime, green, emerald, teal, cyan, sky
    case blue, indigo, violet, purple, fuchsia, pink, rose
}

public struct T3ProjectIdentity: Equatable, Sendable {
    public let monogram: String
    public let color: T3ProjectIconColor

    private static let words = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
    // ECMAScript String.trim whitespace and line terminators.
    private static let whitespace = CharacterSet(
        charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
    )

    public static func derive(from name: String) -> Self {
        let normalized = name.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: whitespace)
        let lowercase = normalized.lowercased(with: Locale(identifier: "en_US"))
        let seed = lowercase.isEmpty ? "project" : lowercase
        let colors = T3ProjectIconColor.allCases
        let index = seed.unicodeScalars.reduce(0) { index, scalar in
            (index * 31 + Int(scalar.value)) % colors.count
        }
        return Self(monogram: monogram(from: normalized), color: colors[index])
    }

    private static func monogram(from name: String) -> String {
        let source = name as NSString
        let matches = words.matches(in: name, range: NSRange(location: 0, length: source.length))
        guard let firstWord = matches.first else { return "PR" }
        let glyphs = source.substring(with: firstWord.range).unicodeScalars
        guard let first = glyphs.first else { return "PR" }

        let digit = glyphs.dropFirst().first { glyph in
            switch glyph.properties.generalCategory {
            case .decimalNumber, .letterNumber, .otherNumber: true
            default: false
            }
        }
        let finalWordInitial = matches.last.flatMap { source.substring(with: $0.range).unicodeScalars.first }
        let second = digit ?? (matches.count > 1 ? finalWordInitial : glyphs.last) ?? first
        let uppercase = (String(first) + String(second)).uppercased()
        return String(uppercase.unicodeScalars.prefix(2))
    }
}
