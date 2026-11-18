import Foundation
import LocalAuthentication

import Security

public enum ApprovalAccessError: LocalizedError, Sendable {
    case keychain
    case busy
    case rejected

    public var errorDescription: String? {
        switch self {
        case .keychain: "Float couldn't access the approvals key in your Keychain."
        case .busy: "Float is updating approval access. Try again in a moment."
        case .rejected: "T3 no longer accepts Float’s approvals key."
        }
    }
}

struct ApprovalKeychain: Sendable {
    let service: String
    let account: String

    struct Record: Codable, Sendable {
        var credential: LocalCredential?
        var retiredSessionIDs: [String] = []
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func load() throws -> Record? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        // The panel can be opened while macOS is locked. Let the caller retry
        // when Keychain cannot grant access without user interaction.
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data) else {
            throw ApprovalAccessError.keychain
        }
        return record
    }

    func save(_ record: Record) throws {
        var attributes = query
        attributes[kSecValueData as String] = try JSONEncoder().encode(record)
        attributes[kSecAttrLabel as String] = "Float approvals"
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [
                kSecValueData as String: attributes[kSecValueData as String]!,
            ] as CFDictionary)
        }
        guard status == errSecSuccess else { throw ApprovalAccessError.keychain }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ApprovalAccessError.keychain }
    }
}

public actor ApprovalAccess {
    private let cli: LocalCLI
    private let keychain: ApprovalKeychain
    private var changing = false

    init(cli: LocalCLI) {
        self.cli = cli
        keychain = ApprovalKeychain(service: "com.dylyoung.float.approvals",
                                    account: cli.base.resolvingSymlinksInPath().path)
    }

    public func enable() async throws {
        guard !changing else { throw ApprovalAccessError.busy }
        changing = true
        defer { changing = false }
        var record = try keychain.load() ?? .init()
        if let current = record.credential {
            if Self.remainingTime(current) > 0 { return }
            record.retiredSessionIDs.append(current.sessionId)
        }
        try await replaceCredential(in: record)
    }

    public func disable() async throws {
        guard !changing else { throw ApprovalAccessError.busy }
        changing = true
        defer { changing = false }
        guard let record = try keychain.load() else { return }
        for id in record.retiredSessionIDs { try await cli.revoke(sessionID: id) }
        if let credential = record.credential { try await cli.revoke(sessionID: credential.sessionId) }
        try keychain.remove()
    }

    public func maintain() async throws -> Bool {
        guard !changing else { throw ApprovalAccessError.busy }
        changing = true
        defer { changing = false }
        guard let record = try keychain.load() else { return false }
        let checked = try await revokeRetired(in: record)
        guard let credential = checked.credential else { return false }
        let remaining = Self.remainingTime(credential)
        if remaining <= 0 {
            try dropCredential(in: checked)
            return false
        }
        if remaining <= 24 * 60 * 60 {
            guard try await cli.hasSession(credential.sessionId) else {
                try dropCredential(in: checked)
                return false
            }
            var next = checked
            next.retiredSessionIDs.append(credential.sessionId)
            try await replaceCredential(in: next)
        }
        return true
    }

    func activeCredential() throws -> LocalCredential {
        guard !changing else { throw ApprovalAccessError.busy }
        guard let record = try keychain.load(), let credential = record.credential else {
            throw ApprovalAccessError.rejected
        }
        guard Self.remainingTime(credential) > 0 else {
            try dropCredential(in: record)
            throw ApprovalAccessError.rejected
        }
        return credential
    }

    func reject(sessionID: String) throws {
        guard !changing, let record = try keychain.load(), record.credential?.sessionId == sessionID else { return }
        try dropCredential(in: record)
    }

    private func replaceCredential(in previous: ApprovalKeychain.Record) async throws {
        var new = previous
        let credential = try await cli.issueApprovals()
        new.credential = credential
        do {
            try keychain.save(new)
        } catch {
            await cli.revoke(credential)
            throw error
        }
        _ = try await revokeRetired(in: new)
    }

    private func revokeRetired(in record: ApprovalKeychain.Record) async throws -> ApprovalKeychain.Record {
        guard !record.retiredSessionIDs.isEmpty else { return record }
        var remaining = record
        remaining.retiredSessionIDs = []
        for id in record.retiredSessionIDs {
            do {
                try await cli.revoke(sessionID: id)
            } catch {
                remaining.retiredSessionIDs.append(id)
            }
        }
        if remaining.retiredSessionIDs != record.retiredSessionIDs {
            if remaining.credential == nil, remaining.retiredSessionIDs.isEmpty {
                try keychain.remove()
            } else {
                try keychain.save(remaining)
            }
        }
        return remaining
    }

    private func dropCredential(in record: ApprovalKeychain.Record) throws {
        if record.retiredSessionIDs.isEmpty {
            try keychain.remove()
        } else {
            try keychain.save(.init(credential: nil, retiredSessionIDs: record.retiredSessionIDs))
        }
    }

    private static func remainingTime(_ credential: LocalCredential) -> TimeInterval {
        t3Date(credential.expiresAt)?.timeIntervalSinceNow ?? 0
    }
}
