import Foundation
import Testing

@testable import FloatCore

private func model(
    _ id: String, label: String, instanceId: String, provider: String, driver: String,
    options: [T3ModelOption] = []
) -> T3Model {
    T3Model(
        selection: T3ModelSelection(instanceId: instanceId, model: id),
        label: label, provider: provider, driverKind: driver, options: options
    )
}

private func provider(
    _ id: String, name: String, driver: String, constraints: [String] = [],
    models: [T3Model]
) -> T3ModelProvider {
    T3ModelProvider(
        instanceId: id, driverKind: driver, displayName: name,
        constraints: constraints, runtimeModes: ["approval-required"],
        omittedModels: 0, models: models
    )
}

@Test func modelRowTrailingIconsKeepCurrentCheckmark() {
    let currentFavourite = T3ModelRowTrailingState(
        isCurrent: true, isFavourite: true, isHovered: false, tab: .provider
    )
    #expect(currentFavourite.showsCheckmark)
    #expect(!currentFavourite.showsRestingFavourite)
    #expect(!currentFavourite.showsFavouriteToggle)

    let hoveredCurrent = T3ModelRowTrailingState(
        isCurrent: true, isFavourite: true, isHovered: true, tab: .favourites
    )
    #expect(hoveredCurrent.showsCheckmark)
    #expect(hoveredCurrent.showsFavouriteToggle)
}

@Test func modelRowTrailingIconsRespectTabAndHover() {
    let providerFavourite = T3ModelRowTrailingState(
        isCurrent: false, isFavourite: true, isHovered: false, tab: .provider
    )
    #expect(providerFavourite.showsRestingFavourite)

    let favouritesRow = T3ModelRowTrailingState(
        isCurrent: false, isFavourite: true, isHovered: false, tab: .favourites
    )
    #expect(!favouritesRow.showsRestingFavourite)

    let hoveredUnstarred = T3ModelRowTrailingState(
        isCurrent: false, isFavourite: false, isHovered: true, tab: .provider
    )
    #expect(hoveredUnstarred.showsFavouriteToggle)
}

@Test func effortOptionRecognizesEveryT3ProviderID() {
    for id in ["effort", "reasoningEffort", "reasoning_effort", "thinking_level"] {
        let option = T3ModelOption(
            id: id, values: [.string("low"), .string("high")],
            defaultValue: .string("low")
        )
        #expect(option.isEffort, "Expected \(id) to be treated as effort")
    }
    #expect(!T3ModelOption(id: "thinking", values: [], defaultValue: nil).isEffort)
}

@Test func effortSelectionUsesTheProvidersOwnOptionID() {
    for id in ["effort", "reasoningEffort", "reasoning_effort", "thinking_level"] {
        let effortModel = model(
            "model", label: "Model", instanceId: "provider", provider: "Provider",
            driver: "custom",
            options: [
                T3ModelOption(
                    id: id, values: [.string("low"), .string("high")],
                    defaultValue: .string("low")
                ),
            ]
        )
        #expect(effortModel.selection(withEffort: "high").options == [
            T3ModelOptionSelection(id: id, value: "high"),
        ])
        #expect(effortModel.selection(withEffort: "default").options == nil)
    }
}

@Test func modelSearchIgnoresCaseSpacesAndPunctuation() {
    let sonnet = model(
        "claude-sonnet-5-5", label: "Sonnet 5.5", instanceId: "claudeAgent",
        provider: "Claude Code", driver: "claudeAgent"
    )
    let sol = model(
        "gpt-5.6-sol", label: "GPT-5.6 Sol", instanceId: "cursor",
        provider: "Cursor", driver: "cursor"
    )

    #expect(T3ModelSearch.matches(sonnet, query: "SON"))
    #expect(T3ModelSearch.matches(sonnet, query: "son net 55"))
    #expect(T3ModelSearch.matches(sol, query: "gpt56"))
    #expect(!T3ModelSearch.matches(sol, query: "son"))
    #expect(T3ModelSearch.serverQuery("gpt56") == "gpt 5 6")
}

@Test func modelSearchGroupsEnabledMatchesInProviderOrder() {
    let claudeModel = model(
        "claude-sonnet-5-5", label: "Sonnet 5.5", instanceId: "claudeAgent",
        provider: "Claude Code", driver: "claudeAgent"
    )
    let cursorModel = model(
        "claude-sonnet-5-5", label: "Claude Sonnet 5.5", instanceId: "cursor",
        provider: "Cursor", driver: "cursor"
    )
    let codexModel = model(
        "gpt-5.6-sol", label: "GPT-5.6 Sol", instanceId: "codex",
        provider: "Codex", driver: "codex"
    )
    let groups = T3ModelSearch.groups(providers: [
        provider("claudeAgent", name: "Claude Code", driver: "claudeAgent", models: [claudeModel]),
        provider("cursor", name: "Cursor", driver: "cursor", models: [cursorModel]),
        provider(
            "codex", name: "Codex", driver: "codex",
            constraints: ["Provider instance is disabled."], models: [codexModel]
        ),
        provider(
            "antigravity", name: "Antigravity", driver: "antigravity",
            models: [
                model(
                    "gemini-carbon", label: "Gemini Carbon", instanceId: "antigravity",
                    provider: "Antigravity", driver: "antigravity"
                ),
            ]
        ),
    ], query: "son")

    #expect(groups.map(\.provider.instanceId) == ["claudeAgent", "cursor"])
    #expect(groups[0].models == [claudeModel])
    #expect(groups[1].models == [cursorModel])
}

@Test func pickerShowsEnabledAndSupportedDisabledProviders() {
    let enabledGrok = provider("grok", name: "Grok", driver: "grok", models: [])
    let disabledGrok = provider(
        "grok", name: "Grok", driver: "grok", constraints: ["Disabled"], models: []
    )
    let disabledOpenCode = provider(
        "opencode", name: "OpenCode", driver: "opencode", constraints: ["Disabled"], models: []
    )

    #expect(enabledGrok.appearsInPicker)
    #expect(!disabledGrok.appearsInPicker)
    #expect(disabledOpenCode.appearsInPicker)
}

@Test func searchCollectsTurnedOffProvidersOnOneLine() {
    let claude = provider(
        "claude", name: "Claude Code", driver: "claudeAgent",
        constraints: ["Provider instance is disabled."], models: []
    )
    let cursor = provider(
        "cursor", name: "Cursor", driver: "cursor",
        constraints: ["Provider instance is disabled."], models: []
    )
    let grok = provider(
        "grok", name: "Grok", driver: "grok",
        constraints: ["Provider instance is disabled."], models: []
    )
    let providers = [claude, cursor, grok]

    #expect(
        T3ModelSearch.turnedOffProviders(providers: providers, query: "son")
            .map(\.pickerName) == ["Claude", "Cursor"]
    )
    #expect(
        T3ModelSearch.turnedOffProviders(providers: providers, query: "grok")
            .map(\.pickerName) == ["Claude", "Cursor", "Grok"]
    )
}

@Test func favouritesStorePreservesSettingsAndKeysByProviderInstance() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "float-favourites-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = directory.appending(path: "settings.json")
    let initial: [String: Any] = [
        "responseStreamingMode": "turn",
        "favorites": [
            ["provider": "claudeAgent-personal", "model": "claude-opus-5-5"],
        ],
    ]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: initial).write(to: settings)

    let store = T3ModelFavouritesStore(settingsURL: settings)
    let existing = T3ModelKey(instanceId: "claudeAgent-personal", model: "claude-opus-5-5")
    let secondInstance = T3ModelKey(instanceId: "claudeAgent-work", model: "claude-opus-5-5")
    let loaded = try await store.load()
    #expect(loaded == [existing])

    let added = try await store.setFavourite(true, key: secondInstance)
    #expect(added == [existing, secondInstance])
    let removed = try await store.setFavourite(false, key: existing)
    #expect(removed == [secondInstance])

    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
    #expect(saved?["responseStreamingMode"] as? String == "turn")
    let favourites = saved?["favorites"] as? [[String: Any]]
    #expect(favourites?.count == 1)
    #expect(favourites?.first?["provider"] as? String == "claudeAgent-work")
    #expect(favourites?.first?["model"] as? String == "claude-opus-5-5")
}

@Test func favouritesStorePreservesSettingsSymlink() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "float-favourites-symlink-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let targetDirectory = directory.appending(path: "shared")
    let target = targetDirectory.appending(path: "settings.json")
    let linkDirectory = directory.appending(path: "userdata")
    let link = linkDirectory.appending(path: "settings.json")
    try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: linkDirectory, withIntermediateDirectories: true)
    try Data(#"{"responseStreamingMode":"turn"}"#.utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let store = T3ModelFavouritesStore(settingsURL: link)
    let favourite = T3ModelKey(instanceId: "codex", model: "gpt-5.6-sol")
    #expect(try await store.setFavourite(true, key: favourite) == [favourite])

    let values = try link.resourceValues(forKeys: [.isSymbolicLinkKey])
    #expect(values.isSymbolicLink == true)
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any]
    #expect(saved?["responseStreamingMode"] as? String == "turn")
    #expect((saved?["favorites"] as? [[String: String]]) == [
        ["provider": "codex", "model": "gpt-5.6-sol"],
    ])
}
