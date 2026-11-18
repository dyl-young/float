import Foundation
import Testing

@testable import FloatCore

private func catalogue(_ ceiling: String?, _ modes: [String: [String]?]) -> T3ModelCatalogue {
    T3ModelCatalogue(runtimeMode: ceiling, providers: modes.map { id, runtimeModes in
        T3ModelProvider(
            instanceId: id, driverKind: id, displayName: id, constraints: [],
            runtimeModes: runtimeModes, omittedModels: 0, models: []
        )
    })
}

@Test func launchesInAutoWhenFloatAndTheProviderAllowIt() {
    let modes = catalogue("auto", [
        "claude": ["approval-required", "auto-accept-edits", "auto", "full-access"],
        "unlisted": nil,
        "empty": [],
    ])
    #expect(modes.launchRuntimeMode(for: "claude") == "auto")
    #expect(modes.launchRuntimeMode(for: "unlisted") == "auto")
    #expect(modes.launchRuntimeMode(for: "empty") == "auto")
    #expect(modes.launchRuntimeMode(for: "unknown-instance") == "auto")
}

@Test func stepsDownToTheBroadestModeTheProviderOffers() {
    let modes = catalogue("auto", [
        "pi": ["approval-required", "auto-accept-edits", "full-access"],
        "kiro": ["approval-required", "full-access"],
        "full-only": ["full-access"],
    ])
    #expect(modes.launchRuntimeMode(for: "pi") == "auto-accept-edits")
    #expect(modes.launchRuntimeMode(for: "kiro") == "approval-required")
    #expect(modes.launchRuntimeMode(for: "full-only") == "approval-required")
}

@Test func staysSupervisedWithoutAnAutoSignIn() {
    let claude = ["claude": ["approval-required", "auto"] as [String]?]
    #expect(catalogue("approval-required", claude).launchRuntimeMode(for: "claude") == "approval-required")
    #expect(catalogue(nil, claude).launchRuntimeMode(for: "claude") == "approval-required")
    #expect(catalogue("full-access", claude).launchRuntimeMode(for: "claude") == "auto")
}

@Test func decodesTheCallerModeFromCapabilities() throws {
    let json = Data("""
    {"runtimeMode":"auto","interactionMode":"default","providers":[
      {"providerInstanceId":"claude","driverKind":"claudeAgent","constraints":[],
       "runtimeModes":["approval-required","auto"],"models":[{"id":"opus"}]}]}
    """.utf8)
    let decoded = try JSONDecoder().decode(T3ModelCatalog.self, from: json).catalogue
    #expect(decoded.runtimeMode == "auto")
    #expect(decoded.launchRuntimeMode(for: "claude") == "auto")
}

@Test func readsSessionIdAndExpiryFromAT3Token() throws {
    let claims = #"{"v":1,"kind":"session","sid":"session-1","sub":"mcp-client","exp":1797292800000}"#
    let payload = Data(claims.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    let credential = try AutoAccessGrant.credential(fromToken: "\(payload).signature")
    #expect(credential.sessionId == "session-1")
    #expect(credential.token == "\(payload).signature")
    #expect(t3Date(credential.expiresAt) == Date(timeIntervalSince1970: 1_797_292_800))
    #expect(throws: T3Error.self) { try AutoAccessGrant.credential(fromToken: "not-a-token") }
}

@Test func takesTheCodeOnlyFromAMatchingApproval() throws {
    let base = "http://127.0.0.1/float/oauth"
    #expect(try AutoAccessGrant.authorizationCode(in: "\(base)?code=abc&state=s1&iss=x", state: "s1") == "abc")
    #expect(throws: T3Error.self) { try AutoAccessGrant.authorizationCode(in: "\(base)?code=abc&state=other", state: "s1") }
    #expect(throws: T3Error.self) { try AutoAccessGrant.authorizationCode(in: "\(base)?error=access_denied&state=s1", state: "s1") }
}

@Test func buildsAnS256ChallengeAndFormBody() {
    // RFC 7636 appendix B.
    #expect(AutoAccessGrant.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let body = String(decoding: AutoAccessGrant.formBody(["b": "a b&c", "a": "x/y"]), as: UTF8.self)
    #expect(body == "a=x%2Fy&b=a%20b%26c")
}
