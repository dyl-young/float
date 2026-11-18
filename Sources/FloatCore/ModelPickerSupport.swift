import Foundation

public enum T3ModelPickerTabContext: Equatable, Sendable {
    case favourites
    case provider
    case search
}

public struct T3ModelRowTrailingState: Equatable, Sendable {
    public let showsFavouriteToggle: Bool
    public let showsRestingFavourite: Bool
    public let showsCheckmark: Bool

    public init(
        isCurrent: Bool, isFavourite: Bool, isHovered: Bool,
        tab: T3ModelPickerTabContext
    ) {
        showsFavouriteToggle = isHovered
        showsRestingFavourite = !isHovered && !isCurrent && isFavourite && tab == .provider
        showsCheckmark = isCurrent
    }
}

public struct T3ModelKey: Codable, Hashable, Sendable {
    public let instanceId: String
    public let model: String

    public init(instanceId: String, model: String) {
        self.instanceId = instanceId
        self.model = model
    }

    public init(_ selection: T3ModelSelection) {
        self.init(instanceId: selection.instanceId, model: selection.model)
    }

    public var selection: T3ModelSelection {
        T3ModelSelection(instanceId: instanceId, model: model)
    }

    public var storageKey: String {
        Data("\(instanceId)\u{0}\(model)".utf8).base64EncodedString()
    }
}

public struct T3ModelSearchGroup: Identifiable, Equatable, Sendable {
    public var id: String { provider.instanceId }
    public let provider: T3ModelProvider
    public let models: [T3Model]
}

extension T3ModelProvider {
    public var hasPickerIcon: Bool {
        ["codex", "openai", "claudeAgent", "cursor", "antigravity", "opencode"]
            .contains(driverKind)
    }

    public var appearsInPicker: Bool { enabled || hasPickerIcon }

    public var pickerName: String {
        switch driverKind {
        case "codex", "openai": "Codex"
        case "claudeAgent": "Claude"
        case "cursor": "Cursor"
        case "antigravity": "Antigravity"
        case "opencode": "OpenCode"
        default: displayName
        }
    }
}

public enum T3ModelSearch {
    public static func normalize(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    public static func matches(_ model: T3Model, query: String) -> Bool {
        let wanted = normalize(query)
        guard !wanted.isEmpty else { return true }
        let candidate = normalize([
            model.label, model.shortLabel, model.selection.model, model.provider,
        ].joined(separator: " "))
        return candidate.contains(wanted)
    }

    public static func groups(
        providers: [T3ModelProvider], query: String
    ) -> [T3ModelSearchGroup] {
        providers.compactMap { provider in
            guard provider.enabled else { return nil }
            let models = provider.models.filter { matches($0, query: query) }
            if !models.isEmpty {
                return T3ModelSearchGroup(provider: provider, models: models)
            }
            return nil
        }
    }

    public static func turnedOffProviders(
        providers: [T3ModelProvider], query: String
    ) -> [T3ModelProvider] {
        let wanted = normalize(query)
        return providers.filter { provider in
            guard !provider.enabled else { return false }
            if provider.hasPickerIcon { return true }
            let name = normalize([provider.displayName, provider.pickerName].joined(separator: " "))
            return !wanted.isEmpty && name.contains(wanted)
        }
    }

    /// T3's server search is punctuation-sensitive. Splitting digit runs lets
    /// compact queries such as "gpt56" retrieve "gpt-5.6" before local matching.
    public static func serverQuery(_ query: String) -> String {
        var parts: [String] = []
        var current = ""
        var previousWasDigit: Bool?
        for character in query.lowercased() where character.isLetter || character.isNumber {
            let isDigit = character.isNumber
            if previousWasDigit != nil, previousWasDigit != isDigit {
                if !current.isEmpty { parts.append(current) }
                current = ""
            }
            if isDigit, previousWasDigit == true {
                if !current.isEmpty { parts.append(current) }
                current = ""
            }
            current.append(character)
            previousWasDigit = isDigit
        }
        if !current.isEmpty { parts.append(current) }
        return parts.joined(separator: " ")
    }
}

public actor T3ModelFavouritesStore {
    private let settingsURL: URL

    public init(settingsURL: URL) {
        self.settingsURL = settingsURL
    }

    public func load() throws -> Set<T3ModelKey> {
        let root = try readRoot()
        guard let values = root["favorites"] as? [[String: Any]] else { return [] }
        return Set(values.compactMap { value in
            guard let instanceId = value["provider"] as? String,
                let model = value["model"] as? String
            else { return nil }
            return T3ModelKey(instanceId: instanceId, model: model)
        })
    }

    @discardableResult
    public func setFavourite(_ favourite: Bool, key: T3ModelKey) throws -> Set<T3ModelKey> {
        var root = try readRoot()
        var favourites = try load()
        if favourite {
            favourites.insert(key)
        } else {
            favourites.remove(key)
        }
        root["favorites"] = favourites
            .sorted { ($0.instanceId, $0.model) < ($1.instanceId, $1.model) }
            .map { ["provider": $0.instanceId, "model": $0.model] }
        let writeURL = settingsURL.resolvingSymlinksInPath()
        let directory = writeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: writeURL, options: .atomic)
        return favourites
    }

    private func readRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value
    }
}
