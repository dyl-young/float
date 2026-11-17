import Foundation
import Testing
@testable import FloatCore

@Test func selectsMatchingSSEEnvelope() throws {
    let data = Data("""
    event: message
    data: {"jsonrpc":"2.0","method":"notifications/progress"}

    event: message
    data: {"jsonrpc":"2.0","id":"target",
    data: "result":{"structuredContent":{"value":"ok"}}}

    """.utf8)
    let envelope = try MCPTransport.envelope(data, matching: "target")
    let result = try MCPTransport.decodeTool(envelope, as: [String: String].self)
    #expect(result == ["value": "ok"])
}

@Test func onlyAcceptsSameOriginUploads() throws {
    let local = LocalRuntime(origin: try #require(URL(string: "http://127.0.0.1:3773")), pid: 1, startedAt: "")
    #expect(try local.uploadURL(relativePath: "/assets/upload?token=a").port == 3773)
    #expect(throws: T3Error.self) { try local.uploadURL(relativePath: "//example.com/upload") }
    #expect(throws: T3Error.self) { try local.uploadURL(relativePath: "https://example.com/upload") }
}

@Test func translatesHostedThreadLinkToTheDesktop() throws {
    let link = try #require(URL(string: "https://app.t3.codes/threads/env-1/mcp%3Alaunch%3A1"))
    let thread = ThreadReference(threadId: "mcp:launch:1", link: link)
    #expect(thread.desktopURL?.absoluteString == "t3code://threads/env-1/mcp%3Alaunch%3A1")
}

@Test func parsesT3Timestamps() {
    #expect(t3Date("2026-11-17T21:30:26.456Z") != nil)
    #expect(t3Date("2026-11-17T21:30:26Z") != nil)
}
