import Foundation
import Testing
@testable import FloatCore

@Test func resolvesFollowUpSettingAndAlternate() {
    #expect(FollowUpMode.setting(in: nil) == .steer)
    let settings = Data(#"{"followUpBehavior":"queue"}"#.utf8)
    let mode = FollowUpMode.setting(in: settings)
    #expect(mode == .queue)
    #expect(mode.resolved(alternate: true, canSteer: true) == .steer)
    #expect(mode.resolved(alternate: true, canSteer: false) == .queue)
    #expect(FollowUpMode.steer.resolved(alternate: false, canSteer: false) == .queue)
}

@Test func readsSteeringFromTheServerItemStatus() {
    #expect(FollowUpState(inputIntent: "steer", status: "pending", knownSteer: false) == .steerWaiting)
    #expect(FollowUpState(inputIntent: "promoted_queued_to_steer", status: "completed", knownSteer: false) == .steerRead)
    #expect(FollowUpState(inputIntent: nil, status: "completed", knownSteer: true) == .steerRead)
    #expect(FollowUpState(inputIntent: "queued_turn", status: "completed", knownSteer: false) == nil)
}

@Test func retriesOnlyOnKnownSteerRejections() {
    #expect(T3Client.steerWasRejected("Thread abc has no running turn that can be steered."))
    #expect(T3Client.steerWasRejected("Wait for context compaction to finish before steering the thread."))
    #expect(!T3Client.steerWasRejected("Could not read the result after dispatch."))
    #expect(!T3Client.steerWasRejected("Permission denied."))
}
