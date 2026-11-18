import Foundation

public struct ComposerTrigger: Equatable, Sendable {
    public enum Kind: Sendable { case skill, slash }

    public let kind: Kind
    public let query: String
    public let range: NSRange
    public var isAtPromptStart: Bool { range.location == 0 }

    public static func detect(in text: String, selection: NSRange) -> Self? {
        guard selection.length == 0, selection.location > 0,
              let caret = Range(selection, in: text)?.lowerBound else { return nil }
        let prefix = text[..<caret]
        let start = prefix.lastIndex(where: \.isWhitespace).map { text.index(after: $0) }
            ?? text.startIndex
        let token = text[start..<caret]
        guard let sigil = token.first, sigil == "$" || sigil == "/",
              !isInsideCode(text[..<start]) else { return nil }
        let query = String(token.dropFirst())
        if sigil == "/" {
            let suffix = text[caret...].prefix(while: { !$0.isWhitespace })
            if (query + suffix).contains(where: { $0 == "/" || $0 == "\\" }) { return nil }
        } else if query.range(of: #"^\.?[0-9][0-9,._]*(?:[kKmMbBtT]|[eE][0-9]+)?[.,;:!?)]*$"#,
                              options: .regularExpression) != nil {
            return nil
        }
        return Self(kind: sigil == "$" ? .skill : .slash, query: query, range: NSRange(start..<caret, in: text))
    }

    private static func isInsideCode(_ prefix: Substring) -> Bool {
        var fence: (marker: Character, width: Int)?
        var inlineWidth: Int?
        for line in prefix.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let indent = line.prefix(while: { $0 == " " }).count
            let content = line.dropFirst(indent)
            if indent < 4, let marker = content.first, marker == "`" || marker == "~" {
                let width = content.prefix(while: { $0 == marker }).count
                if width >= 3 {
                    if let opened = fence {
                        if marker == opened.marker, width >= opened.width,
                           content.dropFirst(width).allSatisfy(\.isWhitespace) {
                            fence = nil
                        }
                        continue
                    }
                    fence = (marker, width)
                    inlineWidth = nil
                    continue
                }
            }
            guard fence == nil else { continue }
            if content.isEmpty { inlineWidth = nil }
            var index = content.startIndex
            while index < content.endIndex {
                if content[index] == "\\", inlineWidth == nil {
                    index = content.index(after: index)
                    if index < content.endIndex { index = content.index(after: index) }
                } else if content[index] == "`" {
                    let run = content[index...].prefix(while: { $0 == "`" })
                    if inlineWidth == nil { inlineWidth = run.count }
                    else if inlineWidth == run.count { inlineWidth = nil }
                    index = run.endIndex
                } else {
                    index = content.index(after: index)
                }
            }
        }
        return fence != nil || inlineWidth != nil
    }

    public func replacementRange(in text: String) -> NSRange {
        let source = text as NSString
        let end = NSMaxRange(range)
        return NSRange(location: range.location,
                       length: range.length + (end < source.length && source.character(at: end) == 32 ? 1 : 0))
    }
}

public struct T3ComposerSkill: Decodable, Equatable, Sendable {
    public let name: String
    public let displayName: String?
    public let shortDescription: String?
    public let description: String?
    public let scope: String?
    public let path: String
    public let enabled: Bool
    public let userInvocable: Bool?

    public var label: String {
        let label = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return label.isEmpty ? name : label
    }

    public var token: String { "$" + name }
}

public struct T3ComposerCommand: Decodable, Equatable, Sendable {
    public struct Input: Decodable, Equatable, Sendable { public let hint: String }

    public let name: String
    public let description: String?
    public let input: Input?
}

public struct T3ComposerInventory: Sendable {
    public let skills: [T3ComposerSkill]
    public let commands: [T3ComposerCommand]

    init(skills: [T3ComposerSkill], commands: [T3ComposerCommand]) {
        self.skills = skills
        self.commands = commands
    }

    public static let empty = Self(skills: [], commands: [])
}

public enum ComposerCompletion: Equatable, Identifiable, Sendable {
    public enum Builtin: String, CaseIterable, Sendable {
        case clear, model

        var description: String {
            switch self {
            case .clear: "Start a new chat"
            case .model: "Switch response model"
            }
        }
    }

    public enum Group: Equatable, Hashable, Sendable { case commands, provider, skills }

    case builtin(Builtin)
    case command(T3ComposerCommand)
    case skill(T3ComposerSkill)

    public var group: Group {
        switch self {
        case .builtin: .commands
        case .command: .provider
        case .skill: .skills
        }
    }

    public var name: String {
        switch self {
        case .builtin(let command): command.rawValue
        case .command(let command): command.name
        case .skill(let skill): skill.name
        }
    }

    public var id: String { "\(group):\(name)" }

    public var description: String {
        switch self {
        case .builtin(let command): command.description
        case .command(let command): command.description ?? command.input?.hint ?? "Run provider command"
        case .skill(let skill):
            skill.shortDescription ?? skill.description ?? skill.scope.map { "\($0) skill" } ?? "Run provider skill"
        }
    }

    public var replacement: String {
        switch self {
        case .builtin: ""
        case .command(let command): "/" + command.name + " "
        case .skill(let skill): skill.token + " "
        }
    }

    public static func matches(
        _ trigger: ComposerTrigger, inventory: T3ComposerInventory, canClear: Bool = true
    ) -> [Self] {
        var seenSkills: Set<String> = []
        let skills = inventory.skills.filter {
            $0.enabled && $0.userInvocable != false
                && seenSkills.insert($0.name.lowercased()).inserted
        }
        var items = skills.map(Self.skill)
        if trigger.kind == .slash {
            let builtins = Builtin.allCases.filter { $0 != .clear || (trigger.isAtPromptStart && canClear) }
            let reserved = Set(["clear", "model", "side", "btw", "compact", "usage-limits"])
            var occupied = seenSkills.union(reserved)
            let providerCommands = trigger.isAtPromptStart ? inventory.commands.filter {
                occupied.insert($0.name.lowercased()).inserted
            } : []
            items = builtins.map(Self.builtin) + providerCommands.map(Self.command) + items
        }
        let query = trigger.query.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == (trigger.kind == .slash ? "/" : "$") }).lowercased()
        guard !query.isEmpty else { return items }
        return items.compactMap { item in
            item.score(query, kind: trigger.kind).map { (item: item, score: $0) }
        }.sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.item.tieBreaker(for: trigger.kind)
                .localizedCompare($1.item.tieBreaker(for: trigger.kind)) == .orderedAscending
        }.map(\.item)
    }

    private func tieBreaker(for kind: ComposerTrigger.Kind) -> String {
        if kind == .skill, case .skill(let skill) = self { return skill.label.lowercased() + "\u{0}" + name }
        switch self {
        case .builtin: return "0" + name
        case .command: return "1" + name
        case .skill: return "2" + name
        }
    }

    private func score(_ query: String, kind: ComposerTrigger.Kind) -> Int? {
        let nameMarkers = "-_/"
        switch self {
        case .skill(let skill):
            let skillQuery = kind == .slash && query.hasPrefix("skill:") ? String(query.dropFirst(6)) : query
            if kind == .slash, query == "skill" || skillQuery.isEmpty { return 0 }
            return [
                Self.match(skill.name, skillQuery, base: 0, markers: nameMarkers, fuzzy: 100),
                Self.match(skill.label, skillQuery, base: 1, fuzzy: 110),
                Self.match(skill.shortDescription, skillQuery, base: 20),
                Self.match(skill.description, skillQuery, base: 30),
                Self.match(skill.scope, skillQuery, base: 40, markers: nil, includes: 44),
            ].compactMap { $0 }.min() ?? (kind == .slash && "skill".hasPrefix(query) ? Int.max : nil)
        default:
            return [
                Self.match(name, query, base: 0, markers: nameMarkers, fuzzy: 100),
                Self.match(description, query, base: 20),
            ].compactMap { $0 }.min()
        }
    }

    private static func match(
        _ input: String?, _ query: String, base: Int, markers: String? = " -_/",
        includes: Int? = nil, fuzzy: Int? = nil
    ) -> Int? {
        guard let value = input?.lowercased(), !value.isEmpty else { return nil }
        let lengthPenalty = min(64, max(0, value.utf16.count - query.utf16.count))
        if value == query { return base }
        if value.hasPrefix(query) { return base + 2 + lengthPenalty }
        if let boundary = markers?.compactMap({ marker -> Int? in
            value.range(of: String(marker) + query, options: .literal).map {
                value[..<$0.lowerBound].utf16.count + 1
            }
        }).min() {
            return base + 4 + 2 * boundary + lengthPenalty
        }
        if let substring = value.range(of: query, options: .literal) {
            return (includes ?? base + 6) + 2 * value[..<substring.lowerBound].utf16.count + lengthPenalty
        }
        guard let fuzzy else { return nil }
        let letters = Array(query.utf16)
        var matches: [Int] = []
        for (index, letter) in value.utf16.enumerated() where letter == letters[matches.count] {
            matches.append(index)
            if matches.count == letters.count {
                let first = matches[0]
                let gap = index - first + 1 - letters.count
                return fuzzy + first * 2 + gap * 4 + lengthPenalty
            }
        }
        return nil
    }
}
