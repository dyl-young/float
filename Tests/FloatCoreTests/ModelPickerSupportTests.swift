import Foundation
import Testing

@testable import FloatCore

private func model(
    _ id: String, label: String, instanceId: String, provider: String, driver: String
) -> T3Model {
    T3Model(
        selection: T3ModelSelection(instanceId: instanceId, model: id),
        label: label, provider: provider, driverKind: driver, options: []
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

@Test func modelSearchGroupsMatchesAndExplainsDisabledProviders() {
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

    #expect(groups.map(\.provider.instanceId) == ["claudeAgent", "cursor", "codex"])
    #expect(groups[0].models == [claudeModel])
    #expect(groups[1].models == [cursorModel])
    #expect(groups[2].models.isEmpty)
    #expect(groups[2].noMatchReason == "Provider instance is disabled.")
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
