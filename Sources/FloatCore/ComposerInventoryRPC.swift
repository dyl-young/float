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
        do {
            let result: ProviderResponse
            if let cwd {
                result = try await rpc.call("server.refreshProviders", WorkspaceInput(instanceId: instanceID, cwd: cwd),
                                            credential: credential)
            } else {
                result = try await rpc.call("server.getConfig", ConfigInput(), credential: credential)
            }
            await cli.revoke(credential)
            guard let provider = result.providers.first(where: { $0.instanceId == instanceID }) else { return .empty }
            let workspace = provider.workspaceSnapshots?.first { $0.cwd == cwd }
            return T3ComposerInventory(skills: workspace?.skills ?? provider.skills ?? [],
                                       commands: workspace?.slashCommands ?? provider.slashCommands ?? [])
        } catch {
            await cli.revoke(credential)
            throw error
        }
    }
}
