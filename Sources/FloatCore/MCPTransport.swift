import Foundation

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct LocalRuntime: Decodable, Equatable, Sendable {
    let origin: URL
    let pid: Int32
    let startedAt: String

    static func load(base: URL) throws -> Self {
        let state = base.appending(path: "userdata/server-runtime.json")
        guard let data = try? Data(contentsOf: state),
            let runtime = try? JSONDecoder().decode(Self.self, from: data),
            runtime.pid > 0, kill(runtime.pid, 0) == 0
        else { throw T3Error.serverUnavailable }
        guard let parts = URLComponents(url: runtime.origin, resolvingAgainstBaseURL: false),
            parts.scheme == "http", ["127.0.0.1", "::1", "[::1]"].contains(parts.host ?? ""),
            parts.port != nil, parts.user == nil, parts.password == nil,
            parts.path.isEmpty || parts.path == "/", parts.query == nil, parts.fragment == nil
        else { throw T3Error.localAddressRequired }
        return runtime
    }

    func uploadURL(relativePath: String) throws -> URL {
        guard relativePath.hasPrefix("/"), !relativePath.hasPrefix("//"),
            let url = URL(string: relativePath, relativeTo: origin)?.absoluteURL,
            url.scheme == origin.scheme, url.host() == origin.host(), url.port == origin.port,
            url.user() == nil, url.password() == nil
        else { throw T3Error.localAddressRequired }
        return url
    }
}

struct LocalCredential: Codable, Sendable {
    let sessionId: String
    let token: String
    let expiresAt: String
}

struct LocalCLI: Sendable {
    let base: URL
    let executable: URL?
    let desktopApp: URL?

    func issue() async throws -> LocalCredential {
        try await issue(subject: "mcp-client", label: "Float", ttl: "1h")
    }

    /// A five-minute owner session that may approve Float's own Auto sign-in (`AutoAccessGrant`).
    func issueApprover() async throws -> LocalCredential {
        try await issue(
            subject: "float-auto-setup", label: "Float setup", ttl: "5m",
            scopes: ["access:write", "orchestration:read", "orchestration:operate"]
        )
    }

    func issueApprovals() async throws -> LocalCredential {
        // Issuance operates on the local T3 database. Check the same live
        // runtime Float will use before provisioning a long-lived session.
        _ = try LocalRuntime.load(base: base)
        return try await issue(subject: "float-approvals", label: "Float approvals", ttl: "30d")
    }

    func revoke(_ credential: LocalCredential) async {
        try? await revoke(sessionID: credential.sessionId)
    }

    func revoke(sessionID: String) async throws {
        _ = try await run(["auth", "session", "revoke", sessionID])
    }

    func hasSession(_ sessionID: String) async throws -> Bool {
        struct Session: Decodable { let sessionId: String }
        let output = try await run(["auth", "session", "list", "--json"])
        guard let sessions = try? JSONDecoder().decode([Session].self, from: output) else {
            throw T3Error.authorization
        }
        return sessions.contains { $0.sessionId == sessionID }
    }

    private func issue(
        subject: String, label: String, ttl: String,
        scopes: [String] = ["orchestration:read", "orchestration:operate"]
    ) async throws -> LocalCredential {
        let output = try await run(
            ["auth", "session", "issue"] + scopes.flatMap { ["--scope", $0] }
                + ["--subject", subject, "--label", label, "--ttl", ttl, "--json"]
        )
        guard let credential = try? JSONDecoder().decode(LocalCredential.self, from: output) else {
            throw T3Error.authorization
        }
        return credential
    }

    private func command() throws -> (executable: URL, prefix: [String]) {
        let files = FileManager.default
        if let executable {
            guard files.isExecutableFile(atPath: executable.path) else { throw T3Error.cliUnavailable }
            return (executable, [])
        }
        let path = ProcessInfo.processInfo.environment["PATH", default: ""]
        let candidates = path.split(separator: ":").filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appending(path: "t3") }
            + [base.appending(path: "bin/t3"),
               files.homeDirectoryForCurrentUser.appending(path: ".t3/bin/t3")]
        if let shim = candidates.first(where: { files.isExecutableFile(atPath: $0.path) }) {
            return (shim, [])
        }
        // The desktop's own CLI shim uses Electron in Node mode with this entry.
        if let desktopApp, let bundle = Bundle(url: desktopApp),
           let executable = bundle.executableURL, let resources = bundle.resourceURL,
           files.isExecutableFile(atPath: executable.path) {
            let archive = resources.appending(path: "app.asar")
            if files.fileExists(atPath: archive.path) {
                return (executable, [archive.path + "/apps/server/dist/bin.mjs"])
            }
        }
        throw T3Error.cliUnavailable
    }

    private func run(_ arguments: [String]) async throws -> Data {
        try await Task.detached {
            let command = try command()
            let process = Process()
            let output = Pipe()
            process.executableURL = command.executable
            process.arguments = command.prefix + arguments + ["--base-dir", base.path]
            if !command.prefix.isEmpty {
                var environment = ProcessInfo.processInfo.environment
                environment["ELECTRON_RUN_AS_NODE"] = "1"
                process.environment = environment
            }
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw T3Error.cliUnavailable
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw T3Error.authorization }
            return data
        }.value
    }
}

/// Streamable HTTP framing follows T3's AcpMcpStdioBridge and MCP tool contracts.
actor MCPTransport {
    private struct Handshake {
        let sessionId: String?
        let protocolVersion: String
    }

    private struct Connected: Sendable {
        let runtime: LocalRuntime
        let credential: LocalCredential
        let handshake: Handshake
    }

    private let cli: LocalCLI
    private let http: URLSession
    private var connection: (runtime: LocalRuntime, task: Task<Connected, Error>)?

    init(cli: LocalCLI) {
        self.cli = cli
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 20
        self.http = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    func call<Result: Decodable & Sendable>(
        _ name: String, _ args: [String: any Sendable], result: Result.Type,
        retryExpiredSession: Bool = false
    ) async throws -> Result {
        let connected = try await connect()
        do {
            let response = try await Self.rpc(
                http: http, runtime: connected.runtime, credential: connected.credential,
                handshake: connected.handshake, method: "tools/call",
                params: ["name": name, "arguments": args], id: UUID().uuidString
            )
            return try Self.decodeTool(response.body, as: result)
        } catch let error as T3Error {
            if case .http(let status) = error, [401, 404].contains(status) {
                await invalidate(connected)
                if retryExpiredSession {
                    try Task.checkCancellation()
                    return try await call(name, args, result: result)
                }
            }
            throw error
        }
    }

    func upload(_ data: Data, mimeType: String, relativePath: String) async throws {
        let runtime = try LocalRuntime.load(base: cli.base)
        var request = URLRequest(url: try runtime.uploadURL(relativePath: relativePath))
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try await Self.fetch(http, request)
    }

    func close() async {
        let previous = connection
        connection = nil
        if let previous, let connected = try? await previous.task.value {
            await terminate(connected)
        }
    }

    private func invalidate(_ connected: Connected) async {
        guard let active = connection, let value = try? await active.task.value,
            connection?.task == active.task,
            value.credential.sessionId == connected.credential.sessionId else { return }
        connection = nil
        await terminate(connected)
    }

    private func terminate(_ connected: Connected) async {
        if let sessionId = connected.handshake.sessionId {
            var request = URLRequest(url: connected.runtime.origin.appending(path: "mcp"))
            request.httpMethod = "DELETE"
            request.timeoutInterval = 2
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
            request.setValue(connected.handshake.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
            request.setValue("Bearer \(connected.credential.token)", forHTTPHeaderField: "Authorization")
            _ = try? await Self.fetch(http, request)
        }
        await cli.revoke(connected.credential)
    }

    private func connect() async throws -> Connected {
        let runtime = try LocalRuntime.load(base: cli.base)
        if let connection, connection.runtime == runtime {
            let current = try await connection.task.value
            if let expiration = t3Date(current.credential.expiresAt),
                expiration.timeIntervalSinceNow > 60 {
                return current
            }
        }
        let previous = connection
        let cli = self.cli
        let http = self.http
        let task = Task {
            let credential: LocalCredential
            do {
                credential = try await AutoAccessGrant.credential(cli: cli, runtime: runtime, http: http)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // An older T3, or a policy that refuses Auto: connect Supervised, as before.
                credential = try await cli.issue()
            }
            do {
                let response = try await Self.rpc(
                    http: http, runtime: runtime, credential: credential, handshake: nil,
                    method: "initialize", params: [
                        "protocolVersion": "2025-06-18",
                        "capabilities": [String: String](),
                        "clientInfo": ["name": "Float", "version": "0.1.0"],
                    ], id: UUID().uuidString
                )
                let result = try Self.result(in: response.body)
                guard let version = result["protocolVersion"] as? String else {
                    throw T3Error.invalidResponse
                }
                let handshake = Handshake(
                    sessionId: response.sessionId, protocolVersion: version
                )
                _ = try await Self.rpc(
                    http: http, runtime: runtime, credential: credential, handshake: handshake,
                    method: "notifications/initialized", params: [:], id: nil
                )
                return Connected(runtime: runtime, credential: credential, handshake: handshake)
            } catch {
                await cli.revoke(credential)
                throw error
            }
        }
        connection = (runtime, task)
        do {
            let connected = try await task.value
            if let previous, let old = try? await previous.task.value { await terminate(old) }
            return connected
        } catch {
            if connection?.task == task { connection = nil }
            if let previous, let old = try? await previous.task.value { await terminate(old) }
            throw error
        }
    }

    private struct Reply {
        let body: [String: Any]
        let sessionId: String?
    }

    private static func rpc(
        http: URLSession, runtime: LocalRuntime, credential: LocalCredential,
        handshake: Handshake?, method: String, params: [String: Any], id: String?
    ) async throws -> Reply {
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        body["id"] = id
        var request = URLRequest(url: runtime.origin.appending(path: "mcp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        if let handshake {
            request.setValue(handshake.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
            request.setValue(handshake.sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await fetch(http, request)
        return Reply(
            body: try id.map { try envelope(data, matching: $0) } ?? [:],
            sessionId: response.value(forHTTPHeaderField: "Mcp-Session-Id")
        )
    }

    private static func fetch(_ session: URLSession, _ request: URLRequest) async throws
        -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw T3Error.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw T3Error.http(response.statusCode) }
        return (data, response)
    }

    static func envelope(_ data: Data, matching id: String) throws -> [String: Any] {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["id"] as? String == id { return object }
        let events = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        for event in events {
            let json = event.components(separatedBy: "\n")
                .filter { $0.hasPrefix("data:") }
                .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            if let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                object["id"] as? String == id { return object }
        }
        throw T3Error.invalidResponse
    }

    private static func result(in envelope: [String: Any]) throws -> [String: Any] {
        if let error = envelope["error"] as? [String: Any], let message = error["message"] as? String {
            throw T3Error.tool(message)
        }
        guard let result = envelope["result"] as? [String: Any] else { throw T3Error.invalidResponse }
        return result
    }

    static func decodeTool<Result: Decodable>(_ envelope: [String: Any], as: Result.Type) throws -> Result {
        let response = try result(in: envelope)
        let content = (response["content"] as? [[String: Any]])?.first?["text"] as? String
        let fallback = content.flatMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        let data = response["structuredContent"] as? [String: Any] ?? fallback
        if let error = data?["message"] as? String,
            response["isError"] as? Bool == true || data?["_tag"] as? String == "OrchestratorMcpFailure" {
            throw T3Error.tool(error)
        }
        if response["isError"] as? Bool == true { throw T3Error.tool(content ?? "T3 couldn’t run the request.") }
        guard let data, let encoded = try? JSONSerialization.data(withJSONObject: data),
            let decoded = try? JSONDecoder().decode(Result.self, from: encoded)
        else { throw T3Error.invalidResponse }
        return decoded
    }
}
