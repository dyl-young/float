import Foundation

struct ComposerInventoryRPC: Sendable {
    private struct WorkspaceInput: Encodable {
        let instanceId: String
        let cwd: String
        let workspaceSnapshotsOnDemand = true
        let providerCatalogsOnDemand = true
    }

    private struct ConfigInput: Encodable {}

    private struct ProviderResponse: Decodable, Sendable {
        struct Provider: Decodable, Sendable {
            struct Workspace: Decodable, Sendable {
                let cwd: String
                let skills: [T3ComposerSkill]
                let slashCommands: [T3ComposerCommand]
            }

            let instanceId: String
            let skills: [T3ComposerSkill]?
            let slashCommands: [T3ComposerCommand]?
            let workspaceSnapshots: [Workspace]?
        }

        let providers: [Provider]
    }

    let rpc: LocalRPC
    let cli: LocalCLI

    func inventory(instanceID: String, cwd: String?) async throws -> T3ComposerInventory {
        let credential = try await cli.issueInventoryReader()
        let result: T3ComposerInventory
        do {
            result = try await readInventory(instanceID: instanceID, cwd: cwd, credential: credential)
        } catch {
            await cli.revoke(credential)
            throw error
        }
        await cli.revoke(credential)
        return result
    }

    private func readInventory(
        instanceID: String, cwd: String?, credential: LocalCredential
    ) async throws -> T3ComposerInventory {
        if let cwd {
            let result: ProviderResponse = try await rpc.call(
                "server.refreshProviders", WorkspaceInput(instanceId: instanceID, cwd: cwd), credential: credential
            )
            if let workspace = result.providers.first(where: { $0.instanceId == instanceID })?
                .workspaceSnapshots?.first(where: { $0.cwd == cwd }) {
                return T3ComposerInventory(skills: workspace.skills, commands: workspace.slashCommands)
            }
            try Task.checkCancellation()
        }
        // The on-demand refresh omits machine lists for providers without a cwd snapshot.
        let config: ProviderResponse = try await rpc.call("server.getConfig", ConfigInput(), credential: credential)
        guard let provider = config.providers.first(where: { $0.instanceId == instanceID }) else { return .empty }
        return T3ComposerInventory(skills: provider.skills ?? [], commands: provider.slashCommands ?? [])
    }
}
