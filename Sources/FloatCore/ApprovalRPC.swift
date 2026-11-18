import Foundation

struct ApprovalRPC: Sendable {
    private struct ProjectionInput: Encodable { let threadId: String }
    private struct DispatchResult: Decodable { let sequence: Int }

    let rpc: LocalRPC
    let access: ApprovalAccess

    func pending(threadID: String) async throws -> [ApprovalRequest] {
        let projection: ApprovalProjection = try await call(
            "orchestration.getThreadProjection", ProjectionInput(threadId: threadID)
        )
        return projection.pendingApprovals
    }

    func respond(_ command: ApprovalCommand) async throws {
        let _: DispatchResult = try await call("orchestration.dispatchCommand", command)
    }

    private func call<Payload: Encodable, Value: Decodable & Sendable>(
        _ method: String, _ payload: Payload
    ) async throws -> Value {
        let credential = try await access.activeCredential()
        do {
            return try await rpc.call(method, payload, credential: credential)
        } catch ApprovalAccessError.rejected {
            try? await access.reject(sessionID: credential.sessionId)
            throw ApprovalAccessError.rejected
        }
    }
}
