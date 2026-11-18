import Foundation
import Testing

@testable import FloatCore

@Test func joinsApprovalDetailsAndKeepsTheOldestPendingRequestFirst() throws {
    let projection = try JSONDecoder().decode(ApprovalProjection.self, from: Data("""
    {
        "runtimeRequests": [
            {"id":"codex","kind":"file-change","status":"pending","responseCapability":{"type":"live"},"createdAt":"2026-11-18T12:03:00Z"},
            {"id":"done","kind":"command","status":"resolved","responseCapability":{"type":"live"},"createdAt":"2026-11-18T11:00:00Z"},
            {"id":"claude","kind":"command","status":"pending","responseCapability":{"type":"live"},"createdAt":"2026-11-18T12:01:00Z"},
            {"id":"gemini","kind":"permission","status":"pending","responseCapability":{"type":"not_resumable"},"createdAt":"2026-11-18T12:04:00Z"},
            {"id":"question","kind":"user_input","status":"pending","responseCapability":{"type":"live"},"createdAt":"2026-11-18T12:00:00Z"}
        ],
        "turnItems": [
            {"type":"approval_request","requestId":"done","requestKind":"command","prompt":"echo done"},
            {"type":"approval_request","requestId":"claude","requestKind":"command","prompt":"echo float-approval-test","reason":"Verify output"},
            {"type":"approval_request","requestId":"codex","requestKind":"file-change","prompt":"Update the changelog","paths":["CHANGELOG.md"],"options":[{"decision":"accept"},{"decision":"decline"},{"decision":"acceptForSession"}]},
            {"type":"approval_request","requestId":"gemini","requestKind":"permission","prompt":"Read project metadata"},
            {"type":"user_input_request","requestId":"question","options":["Do not treat this as an approval"]}
        ]
    }
    """.utf8))

    let approvals = projection.pendingApprovals
    #expect(approvals.map(\.id) == ["claude", "codex", "gemini"])
    let claude = try #require(approvals.first { $0.id == "claude" })
    #expect(claude.command == "echo float-approval-test")
    #expect(claude.detail == nil)
    #expect(claude.reason == "Verify output")
    #expect(claude.allowedDecisions == [.allow, .deny])
    let codex = try #require(approvals.first { $0.id == "codex" })
    #expect(codex.action == "Wants to change files")
    #expect(codex.detail == "Update the changelog")
    #expect(codex.paths == ["CHANGELOG.md"])
    #expect(codex.allowedDecisions == [.allow, .deny])
    let gemini = try #require(approvals.first { $0.id == "gemini" })
    #expect(gemini.summary == "Read project metadata")
    #expect(gemini.allowedDecisions.isEmpty)
}

@Test func keepsMcpApplicationContextAndUsesOnlyTheOfferedOneTimeDecisions() throws {
    let projection = try JSONDecoder().decode(ApprovalProjection.self, from: Data("""
    {
        "runtimeRequests": [
            {"id":"mcp","kind":"mcp-elicitation","status":"pending","responseCapability":{"type":"live"},"createdAt":"2026-11-18T12:01:00Z"}
        ],
        "turnItems": [
            {"type":"approval_request","requestId":"mcp","requestKind":"mcp-elicitation","appName":"Calendar","prompt":"Needs access to your calendars","options":[{"decision":"acceptAlways"},{"decision":"decline"}]}
        ]
    }
    """.utf8))
    let request = try #require(projection.pendingApprovals.first)
    #expect(request.action == "Needs input for Calendar")
    #expect(request.detail == "Needs access to your calendars")
    #expect(request.allowedDecisions == [.deny])
}

@Test func encodesExactApprovalDecisionPayloads() throws {
    func command(_ decision: ApprovalDecision) throws -> [String: String] {
        let request = ApprovalCommand(threadId: "thread-1", requestId: "request-7", decision: decision)
        return try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(request))
    }
    let allow = try command(.allow)
    let deny = try command(.deny)
    let allowID = try #require(allow["commandId"])
    let denyID = try #require(deny["commandId"])
    #expect(UUID(uuidString: allowID) != nil)
    #expect(UUID(uuidString: denyID) != nil)
    #expect(allowID != denyID)
    #expect(allow == [
        "type": "runtime-request.respond", "commandId": allowID,
        "threadId": "thread-1", "requestId": "request-7", "decision": "accept",
    ])
    #expect(deny == [
        "type": "runtime-request.respond", "commandId": denyID,
        "threadId": "thread-1", "requestId": "request-7", "decision": "decline",
    ])
}

@Test func approvalAccessPersistsTheCredentialOnlyInKeychain() async throws {
    let files = FileManager.default
    let home = files.temporaryDirectory.appending(path: "Float-approvals-\(UUID())", directoryHint: .isDirectory)
    let userdata = home.appending(path: "userdata", directoryHint: .isDirectory)
    try files.createDirectory(at: userdata, withIntermediateDirectories: true)
    let keychain = ApprovalKeychain(service: "com.dylyoung.float.approvals", account: home.resolvingSymlinksInPath().path)
    defer {
        try? keychain.remove()
        try? files.removeItem(at: home)
    }

    let runtime = """
    {"origin":"http://127.0.0.1:47891","pid":\(ProcessInfo.processInfo.processIdentifier),"startedAt":"fixture"}
    """
    let runtimeFile = userdata.appending(path: "server-runtime.json")
    try Data(runtime.utf8).write(to: runtimeFile)

    let executable = home.appending(path: "t3", directoryHint: .notDirectory)
    let fakeCLI = #"""
    #!/bin/sh
    case "$3" in
      issue)
        token=$(/usr/bin/uuidgen)
        id=$(/usr/bin/uuidgen)
        expiry=$(/bin/date -u -v+30d '+%Y-%m-%dT%H:%M:%SZ')
        printf '{"sessionId":"%s","token":"%s","expiresAt":"%s"}\n' "$id" "$token" "$expiry"
        ;;
      revoke) exit 0 ;;
      *) exit 1 ;;
    esac
    """#
    try Data(fakeCLI.utf8).write(to: executable)
    try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let client = T3Client(base: home, executable: executable)
    try await client.approvals.enable()
    let stored = try keychain.load()
    let hasCredential = stored?.credential != nil
    try #require(hasCredential)
    let credential = stored!.credential!
    let sensitiveValues = [credential.token, credential.sessionId]
    let enabled = try await client.approvals.maintain()
    #expect(enabled)
    let defaults = UserDefaults.standard.dictionaryRepresentation()
    let defaultsJSON = try PropertyListSerialization.data(fromPropertyList: defaults, format: .xml, options: 0)
    let leaksIntoDefaults = sensitiveValues.contains { defaultsJSON.range(of: Data($0.utf8)) != nil }
    #expect(!leaksIntoDefaults)
    let created = try files.subpathsOfDirectory(atPath: home.path).sorted()
    #expect(created == ["t3", "userdata", "userdata/server-runtime.json"])
    for file in [runtimeFile, executable] {
        let contents = try Data(contentsOf: file)
        let containsCredential = sensitiveValues.contains { contents.range(of: Data($0.utf8)) != nil }
        #expect(!containsCredential)
    }

    try await client.approvals.disable()
    let removed = try keychain.load() == nil
    #expect(removed)
}

@Test func findsTheExactAntigravityCommandInTheSameProviderTurn() throws {
    let projection = try JSONDecoder().decode(ApprovalProjection.self, from: Data("""
    {
        "runtimeRequests": [
            {"id":"acp","kind":"command","status":"pending","responseCapability":{"type":"live"},"createdAt":"2026-11-18T12:01:00Z"}
        ],
        "turnItems": [
            {"type":"command_execution","providerTurnId":"turn-1","nativeItemRef":{"driver":"antigravity","nativeId":"tool-2"},"input":"echo different-turn"},
            {"type":"command_execution","providerTurnId":"turn-2","nativeItemRef":{"driver":"antigravity","nativeId":"tool-2"},"input":"bash -c \\"echo float-approval-test\\""},
            {"type":"approval_request","providerTurnId":"turn-2","nativeItemRef":{"driver":"antigravity","nativeId":"tool-2"},"requestId":"acp","requestKind":"command","prompt":"Ran command"}
        ]
    }
    """.utf8))
    let approval = try #require(projection.pendingApprovals.first)
    #expect(approval.command == "bash -c \"echo float-approval-test\"")
    #expect(approval.detail == nil)
    #expect(approval.allowedDecisions == [.allow, .deny])
}

@Test func recognizesPendingApprovalStatusesFromMcp() throws {
    for status in ["waiting", "running", "pending", "completed"] {
        let item = try JSONDecoder().decode(ThreadSnapshot.Item.self, from: Data("""
        {"itemId":"approval","position":0,"type":"approval_request","status":"\(status)","textTruncated":false,"updatedAt":"2026-11-18T12:01:00Z"}
        """.utf8))
        #expect(item.isPendingApproval == (status != "completed"))
    }
}
