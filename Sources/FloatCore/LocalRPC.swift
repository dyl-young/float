import Foundation

enum ApprovalRPCError: Error {
    case unavailable
    case invalidReply
    case commandFailed
}

/// Loopback V2 Effect RPC shared by approvals and provider inventory.
struct LocalRPC: Sendable {
    private struct Ticket: Decodable { let ticket: String }

    private struct Request<Payload: Encodable>: Encodable {
        let _tag = "Request"
        let id = "1"
        let tag: String
        let payload: Payload
        let headers: [[String]] = []
    }

    private struct Reply<Value: Decodable>: Decodable {
        struct Exit: Decodable {
            let _tag: String
            let value: Value?
        }

        let _tag: String
        let requestId: String?
        let exit: Exit?

        enum CodingKeys: String, CodingKey { case _tag, requestId, exit }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            _tag = try values.decode(String.self, forKey: ._tag)
            requestId = (try? values.decode(String.self, forKey: .requestId))
                ?? (try? values.decode(Int.self, forKey: .requestId)).map(String.init)
            exit = try values.decodeIfPresent(Exit.self, forKey: .exit)
        }
    }

    private let base: URL
    private let http: URLSession

    init(base: URL) {
        self.base = base
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 8
        self.http = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    func call<Payload: Encodable, Value: Decodable & Sendable>(
        _ method: String, _ payload: Payload, credential: LocalCredential
    ) async throws -> Value {
        let runtime = try LocalRuntime.load(base: base)
        let ticket = try await issueTicket(for: runtime, credential: credential)

        guard var url = URLComponents(url: runtime.origin, resolvingAgainstBaseURL: false) else {
            throw ApprovalRPCError.invalidReply
        }
        url.scheme = "ws"
        url.path = "/ws"
        url.queryItems = [
            URLQueryItem(name: "orchestrationProtocol", value: "2"),
            URLQueryItem(name: "wsTicket", value: ticket.ticket),
        ]
        guard let endpoint = url.url else { throw ApprovalRPCError.invalidReply }
        let socket = http.webSocketTask(with: endpoint)
        socket.maximumMessageSize = 32 * 1024 * 1024
        let data = try JSONEncoder().encode(Request(tag: method, payload: payload))
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    do {
                        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
                        return try await Self.readReply(socket)
                    } catch let error as ApprovalRPCError {
                        throw error
                    } catch {
                        // System error descriptions can include the ticket-bearing URL.
                        throw ApprovalRPCError.unavailable
                    }
                } onCancel: {
                    socket.cancel(with: .goingAway, reason: nil)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw ApprovalRPCError.unavailable
            }
            defer { group.cancelAll() }
            guard let reply = try await group.next() else { throw ApprovalRPCError.unavailable }
            return reply
        }
    }

    private func issueTicket(for runtime: LocalRuntime, credential: LocalCredential) async throws -> Ticket {
        var request = URLRequest(url: runtime.origin.appending(path: "api/auth/websocket-ticket/rpc"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw ApprovalRPCError.unavailable
        }
        guard let response = response as? HTTPURLResponse else { throw ApprovalRPCError.invalidReply }
        if [401, 403].contains(response.statusCode) {
            throw ApprovalAccessError.rejected
        }
        guard response.statusCode == 200,
              let ticket = try? JSONDecoder().decode(Ticket.self, from: data) else {
            throw ApprovalRPCError.invalidReply
        }
        return ticket
    }

    private static func readReply<Value: Decodable>(_ socket: URLSessionWebSocketTask) async throws -> Value {
        let decoder = JSONDecoder()
        while !Task.isCancelled {
            let data: Data
            switch try await socket.receive() {
            case .data(let bytes): data = bytes
            case .string(let text): data = Data(text.utf8)
            @unknown default: throw ApprovalRPCError.invalidReply
            }
            let replies: [Reply<Value>]
            if let single = try? decoder.decode(Reply<Value>.self, from: data) {
                replies = [single]
            } else {
                guard let batch = try? decoder.decode([Reply<Value>].self, from: data) else {
                    throw ApprovalRPCError.invalidReply
                }
                replies = batch
            }
            for reply in replies {
                guard reply._tag == "Exit", reply.requestId == "1", let exit = reply.exit else { continue }
                guard exit._tag == "Success", let value = exit.value else { throw ApprovalRPCError.commandFailed }
                return value
            }
        }
        throw CancellationError()
    }
}
