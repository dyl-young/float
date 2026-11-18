import CryptoKit
import Foundation

/// Signs Float in to T3 as an MCP app approved for Auto, so the threads it starts can run in Auto.
///
/// T3 caps a session issued with `t3 auth session issue` at Supervised, and only its MCP sign-in
/// (OAuth with PKCE) records a broader mode. Float approves its own sign-in with a five-minute owner
/// session from the local CLI, the same trust it already uses to issue sessions, and revokes that
/// session straight away. No browser is involved and nothing is written to disk: the token lives as
/// long as the MCP connection, which revokes it when it closes. If Float crashes first, the session
/// stays listed in T3 until it expires, but nobody holds its token.
enum AutoAccessGrant {
    static let access = "auto"
    static let clientName = "Float"
    /// Registered but never opened: the code comes back in the decision's JSON, not a redirect.
    static let redirectURI = "http://127.0.0.1/float/oauth"

    private struct Registered: Decodable { let client_id: String }
    private struct Approval: Decodable {
        let csrfToken: String?
        let oneClickAccess: [String]?
    }
    private struct Decision: Decodable { let redirectTo: String }
    private struct Token: Decodable { let access_token: String }

    static func credential(cli: LocalCLI, runtime: LocalRuntime, http: URLSession) async throws -> LocalCredential {
        let approver = try await cli.issueApprover()
        defer { Task.detached { try? await cli.revoke(sessionID: approver.sessionId) } }

        let registered: Registered = try await post(http, runtime, "oauth/mcp/register", json: [
            "client_name": clientName, "redirect_uris": [redirectURI],
            "token_endpoint_auth_method": "none",
        ])
        let verifier = randomURLSafe(bytes: 32)
        let state = randomURLSafe(bytes: 16)
        let authorization: [String: String] = [
            "response_type": "code", "client_id": registered.client_id, "redirect_uri": redirectURI,
            "code_challenge": challenge(for: verifier), "code_challenge_method": "S256",
            "state": state, "resource": runtime.origin.appending(path: "mcp").absoluteString,
        ]
        let bearer = "Bearer \(approver.token)"
        let approval: Approval = try await post(
            http, runtime, "oauth/mcp/approval", json: authorization, authorization: bearer
        )
        guard let csrf = approval.csrfToken, approval.oneClickAccess?.contains(access) == true else {
            throw T3Error.authorization
        }
        let decision: Decision = try await post(http, runtime, "oauth/mcp/decision", json: [
            "authorization": authorization,
            "decision": ["_tag": "browser-session", "access": access, "csrfToken": csrf],
        ], authorization: bearer)
        let code = try authorizationCode(in: decision.redirectTo, state: state)
        let token: Token = try await post(http, runtime, "oauth/mcp/token", form: [
            "grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI,
            "client_id": registered.client_id, "code_verifier": verifier,
            "resource": authorization["resource"]!,
        ])
        return try credential(fromToken: token.access_token)
    }

    /// T3 session tokens are `base64url(claims).signature`; the claims carry the session id and expiry.
    static func credential(fromToken token: String) throws -> LocalCredential {
        struct Claims: Decodable {
            let sid: String
            let exp: Double
        }
        guard let payload = token.split(separator: ".").first,
              let data = base64URLDecode(String(payload)),
              let claims = try? JSONDecoder().decode(Claims.self, from: data) else {
            throw T3Error.invalidResponse
        }
        let expiry = Date(timeIntervalSince1970: claims.exp / 1000)
        return LocalCredential(
            sessionId: claims.sid, token: token,
            expiresAt: expiry.ISO8601Format(.iso8601.year().month().day().time(includingFractionalSeconds: true))
        )
    }

    static func authorizationCode(in redirect: String, state: String) throws -> String {
        guard let items = URLComponents(string: redirect)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == state,
              items.first(where: { $0.name == "error" }) == nil,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw T3Error.authorization
        }
        return code
    }

    static func challenge(for verifier: String) -> String {
        base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = fields.sorted { $0.key < $1.key }.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(encoded)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func randomURLSafe(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URLEncode(Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func post<Value: Decodable>(
        _ http: URLSession, _ runtime: LocalRuntime, _ path: String,
        json: [String: Any]? = nil, form: [String: String]? = nil, authorization: String? = nil
    ) async throws -> Value {
        var request = URLRequest(url: runtime.origin.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody(form)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw T3Error.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw T3Error.http(response.statusCode) }
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else { throw T3Error.invalidResponse }
        return value
    }
}
