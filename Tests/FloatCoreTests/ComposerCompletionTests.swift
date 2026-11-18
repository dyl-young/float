import Foundation
import Testing

@testable import FloatCore

private func trigger(_ text: String, caret: Int? = nil, length: Int = 0) -> ComposerTrigger? {
    ComposerTrigger.detect(in: text, selection: NSRange(location: caret ?? text.utf16.count, length: length))
}

private func skill(
    _ name: String, label: String? = nil, shortDescription: String? = nil,
    description: String? = nil, enabled: Bool = true, userInvocable: Bool? = nil
) -> T3ComposerSkill {
    T3ComposerSkill(name: name, displayName: label, shortDescription: shortDescription,
                    description: description, scope: "project", path: "/fixture/\(name)/SKILL.md",
                    enabled: enabled, userInvocable: userInvocable)
}

@Test func composerTriggersOnlyAtWordStartsAndUseUTF16Offsets() throws {
    let skill = try #require(trigger("👋 hello\t$sta"))
    #expect(skill.kind == .skill)
    #expect(skill.query == "sta")
    #expect(skill.range == NSRange(location: 9, length: 4))
    #expect(!skill.isAtPromptStart)

    let slash = try #require(trigger("/rev"))
    #expect(slash.kind == .slash)
    #expect(slash.isAtPromptStart)
    #expect(trigger("again\n/rev")?.isAtPromptStart == false)
    #expect(trigger(" /rev")?.isAtPromptStart == false)
    #expect(trigger("say $sta end", caret: 8)?.query == "sta")
    #expect(trigger("say $sta end", caret: 4, length: 4) == nil)

    for literal in ["word$sta", "word/rev", "($sta", "https://", "/Users/dylan", "$12.50", "plain "] {
        #expect(trigger(literal) == nil, "Unexpected trigger in \(literal)")
    }
    #expect(trigger("/Users/dylan", caret: 3) == nil)
}

@Test func composerIgnoresCodeAndResumesAfterItsClosingDelimiter() {
    for code in [
        "`echo $sta", "``echo ` /rev", "```sh\necho $sta", "~~~text\n/rev",
        "Intro\n  ```\n$sta", "```\n~~~\n$sta",
    ] {
        #expect(trigger(code) == nil, "Unexpected trigger in \(code)")
    }
    #expect(trigger("`inline` $sta")?.query == "sta")
    #expect(trigger("``nested ` delimiter`` /rev")?.query == "rev")
    #expect(trigger("~~~sh\necho yes\n~~~~\n$sta")?.query == "sta")
    #expect(trigger("\\`literal $sta")?.query == "sta")
}

@Test func skillsRankNamesThenDisplayAndDescriptionMatches() throws {
    let inventory = T3ComposerInventory(skills: [
        skill("body", description: "Review"),
        skill("scan", shortDescription: "Review"),
        skill("examine", label: "Review"),
        skill("review", enabled: false),
        skill("review"),
        skill("REVIEW"),
        skill("reviewer"),
        skill("reviewer-agent", userInvocable: false),
        skill("rev-iew"),
        skill("other"),
    ], commands: [])
    let active = try #require(trigger("$REVIEW"))
    #expect(ComposerCompletion.matches(active, inventory: inventory).map(\.name)
        == ["review", "examine", "reviewer", "scan", "body", "rev-iew"])

    let bareSkill = try #require(trigger("$"))
    #expect(ComposerCompletion.matches(bareSkill, inventory: inventory).map(\.name)
        == ["body", "scan", "examine", "review", "reviewer", "rev-iew", "other"])
}

@Test func slashSearchRestrictsCommandsToTheirSupportedPromptPositions() throws {
    let inventory = T3ComposerInventory(skills: [skill("review"), skill("standup")], commands: [
        .init(name: "review", description: nil, input: nil),
        .init(name: "init", description: "Initialise", input: nil),
        .init(name: "clear", description: nil, input: nil),
        .init(name: "side", description: nil, input: nil),
    ])
    let start = try #require(trigger("/"))
    let later = try #require(trigger("hello /"))
    let skillSearch = try #require(trigger("hello /skill:st"))
    #expect(ComposerCompletion.matches(start, inventory: inventory).map(\.name)
        == ["clear", "model", "init", "review", "standup"])
    #expect(ComposerCompletion.matches(later, inventory: inventory).map(\.name)
        == ["model", "review", "standup"])
    #expect(ComposerCompletion.matches(skillSearch, inventory: inventory).map(\.name)
        == ["standup"])
    #expect(ComposerCompletion.matches(start, inventory: .empty, canClear: false)
        == [.builtin(.model)])
    #expect(ComposerCompletion.matches(
        try #require(trigger("/init")), inventory: inventory
    ).first?.replacement == "/init ")
}

@Test func composerReplacementSwallowsOnlyTheExistingSeparatingSpace() throws {
    let text = "👋 /skill:sta then"
    let active = try #require(trigger(text, caret: 13))
    #expect(active.query == "skill:sta")
    #expect((text as NSString).substring(with: active.replacementRange(in: text)) == "/skill:sta ")
}

@Test func draftSerialisesSkillNamesAndPreservesSurroundingText() throws {
    let first = ComposerSkillChip(name: "standup-notes", label: "Standup Notes")
    let second = ComposerSkillChip(name: "plugin:review", label: "Review")
    let editorText = "👋 \(ComposerDraft.attachmentCharacter) then \(ComposerDraft.attachmentCharacter) please"
    let draft = ComposerDraft(editorText, chips: [3: first, 10: second, 999: second, 0: first])
    #expect(draft.text == "👋 $standup-notes then $plugin:review please")
    #expect(draft.sendText(in: NSRange(location: 3, length: 8)) == "$standup-notes then $plugin:review")
    #expect(draft.chips.count == 2)

    let stored = try PropertyListEncoder().encode(draft)
    let restored = try PropertyListDecoder().decode(ComposerDraft.self, from: stored)
    #expect(restored == draft)
}

@Test func backspaceDeletesExactlyOneChipAndItsSeparatingSpace() throws {
    let chip = ComposerSkillChip(name: "review", label: "Review")
    let text = "👋 \(ComposerDraft.attachmentCharacter) next"
    let draft = ComposerDraft(text, chips: [3: chip])
    #expect(draft.chipDeletionRange(before: 4) == NSRange(location: 3, length: 1))
    let range = try #require(draft.chipDeletionRange(before: 5))
    #expect(range == NSRange(location: 3, length: 2))
    #expect((text as NSString).replacingCharacters(in: range, with: "") == "👋 next")
    #expect(draft.chipDeletionRange(before: 6) == nil)
    #expect(draft.chipDeletionRange(before: 0) == nil)
    #expect(ComposerDraft("plain ").chipDeletionRange(before: 6) == nil)
}

@Test func messageSkillMatchingUsesWholeKnownTokens() {
    let chip = ComposerSkillChip(name: "plugin:review", label: "Review")
    let text = "Use $plugin:review or $other. word$plugin:review"
    let matches = ComposerSkillChip.matches(in: text, chips: [chip])
    #expect(matches.map { String(text[$0.range]) } == ["$plugin:review"])
    #expect(matches.map(\.chip) == [chip])
}
