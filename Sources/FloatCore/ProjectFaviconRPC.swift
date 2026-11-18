import Foundation

actor ProjectFaviconRPC {
    private struct Input: Encodable {
        struct Resource: Encodable {
            let _tag = "project-favicon"
            let cwd: String
            let path: String?
        }
        let resource: Resource
    }

    private struct AssetURL: Decodable {
        let relativeUrl: String
    }

    private let rpc: LocalRPC
    private let cli: LocalCLI
    private var reader: (task: Task<LocalCredential, Error>, issuedAt: ContinuousClock.Instant)?
    private var closed = false

    init(rpc: LocalRPC, cli: LocalCLI) {
        self.rpc = rpc
        self.cli = cli
    }

    func data(cwd: String, path: String?) async throws -> Data? {
        let credential = try await credential()
        let input = Input(resource: .init(cwd: cwd, path: path))
        let asset: AssetURL = try await rpc.call("assets.createUrl", input, credential: credential)
        return try await rpc.projectFavicon(relativePath: asset.relativeUrl)
    }

    func close() async {
        closed = true
        let task = reader?.task
        reader = nil
        if let task, let credential = try? await task.value { await cli.revoke(credential) }
    }

    private func credential() async throws -> LocalCredential {
        guard !closed else { throw CancellationError() }
        // Share the read-only session across rows. Rotate before the server's five-minute expiry.
        if let reader, reader.issuedAt.duration(to: .now) < .seconds(240) {
            return try await reader.task.value
        }

        let previous = reader?.task
        let issuedAt = ContinuousClock.now
        let task = Task { [cli] in try await cli.issueProjectFaviconReader() }
        reader = (task, issuedAt)
        if let previous, let credential = try? await previous.value { await cli.revoke(credential) }
        do {
            return try await task.value
        } catch {
            if reader?.issuedAt == issuedAt { reader = nil }
            throw error
        }
    }
}
