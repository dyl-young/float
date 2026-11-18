import Testing

@testable import FloatCore

private let singleQuestion = T3Question(
    id: "scope", header: "Scope", question: "Which folders?",
    options: [
        .init(label: "Untouched for 30+ days", description: "14 folders", value: "stale"),
        .init(label: " Just list them ", description: "Delete nothing"),
    ],
    allowCustomAnswer: false
)

@Test(arguments: [
    ("Feature-based", "Feature-based", nil),
    ("  Feature-based. ", "\n FEATURE-BASED?!  ", nil),
    ("Feature-based (grouped by domain)", "feature-based…", nil),
    ("Feature-based", "Feature-based by domain", "Feature-based by domain"),
    ("Feature-based", "  Group by domain.  ", "Group by domain."),
    ("Feature-based", "Based", "Based"),
    ("Feature-based", " \n ", nil),
] as [(String, String, String?)])
func hidesRedundantQuestionOptionDescriptions(
    label: String, description: String, expected: String?
) {
    let option = T3Question.Option(label: label, description: description)
    #expect(option.displayDescription == expected)
}

@Test func buildsSingleSelectAnswersFromOptionValuesAndLabels() {
    #expect(
        T3QuestionAnswerBuilder.build(
            questions: [singleQuestion],
            drafts: ["scope": .init(selectedOptionValues: ["stale"])]
        ) == ["scope": .text("stale")]
    )
    #expect(
        T3QuestionAnswerBuilder.build(
            questions: [singleQuestion],
            drafts: ["scope": .init(selectedOptionValues: ["Just list them"])]
        ) == ["scope": .text("Just list them")]
    )
}

@Test func buildsMultiSelectAnswersInSelectionOrderWithoutDuplicates() {
    let question = T3Question(
        id: "areas", header: "Areas", question: "Which areas?",
        options: [
            .init(label: "Server", description: "", value: "server"),
            .init(label: "Web", description: ""),
        ],
        multiSelect: true, allowCustomAnswer: false
    )
    #expect(
        T3QuestionAnswerBuilder.build(
            questions: [question],
            drafts: ["areas": .init(selectedOptionValues: ["Web", "server", "Web"])]
        ) == ["areas": .selections(["Web", "server"])]
    )
}

@Test func buildsCustomTextAnswersAndPreservesInitialEditorText() {
    let custom = T3Question(
        id: "notes", header: "Notes", question: "Anything else?",
        options: [], allowCustomAnswer: true
    )
    let initial = T3Question(
        id: "message", header: "Message", question: "Edit this",
        options: [], allowCustomAnswer: true, initialAnswer: "  Proposed\n"
    )
    #expect(
        T3QuestionAnswerBuilder.build(
            questions: [custom, initial],
            drafts: [
                "notes": .init(customAnswer: "  Only generated folders  "),
                "message": .init(customAnswer: "  Edited message\n"),
            ]
        ) == [
            "notes": .text("Only generated folders"),
            "message": .text("  Edited message\n"),
        ]
    )
}

@Test func rejectsIncompleteRequiredAnswersAndIgnoresDisallowedCustomText() {
    #expect(
        T3QuestionAnswerBuilder.build(
            questions: [singleQuestion],
            drafts: ["scope": .init(customAnswer: "Something else")]
        ) == nil
    )
    #expect(
        T3QuestionAnswerBuilder.build(questions: [singleQuestion], drafts: [:]) == nil
    )
}

@Test func advancesLocallyAndKeepsPickedAnswersWhenGoingBack() {
    let second = T3Question(
        id: "report", header: "Report", question: "Include a summary?",
        options: [.init(label: "Include summary", description: "", value: "yes")],
        allowCustomAnswer: false
    )
    var flow = T3QuestionFlow(request: .init(requestId: "request", questions: [singleQuestion, second]))
    let backedFromFirst = flow.goBack()
    #expect(!backedFromFirst)
    #expect(flow.confirm() == nil)

    flow.select(singleQuestion.options[0])
    #expect(flow.confirm() == .advanced)
    #expect(flow.index == 1)
    #expect(!flow.canAdvance)
    flow.select(second.options[0])

    let backed = flow.goBack()
    #expect(backed)
    #expect(flow.index == 0)
    #expect(flow.isSelected(singleQuestion.options[0]))
    flow.select(singleQuestion.options[1])
    #expect(flow.confirm() == .advanced)
    #expect(flow.isSelected(second.options[0]))
    #expect(flow.confirm() == .submit(["scope": .text("Just list them"), "report": .text("yes")]))
}

@Test func restoresCustomComposerTextAndMultiSelectDraftsAcrossSteps() {
    let custom = T3Question(
        id: "notes", header: "Notes", question: "Anything else?",
        options: [], allowCustomAnswer: true
    )
    let multiple = T3Question(
        id: "areas", header: "Areas", question: "Which areas?",
        options: [
            .init(label: "Server", description: "", value: "server"),
            .init(label: "Web", description: "", value: "web"),
        ],
        multiSelect: true, allowCustomAnswer: false
    )
    var flow = T3QuestionFlow(request: .init(requestId: "request", questions: [custom, multiple]))
    flow.setCustomAnswer("  Only generated folders  ")
    #expect(flow.confirm() == .advanced)
    #expect(flow.composerText.isEmpty)
    flow.select(multiple.options[1])
    flow.select(multiple.options[0])

    let backed = flow.goBack()
    #expect(backed)
    #expect(flow.composerText == "  Only generated folders  ")
    #expect(flow.confirm() == .advanced)
    #expect(flow.confirm() == .submit([
        "notes": .text("Only generated folders"), "areas": .selections(["web", "server"]),
    ]))
}

@Test func jumpingToTheLastQuestionKeepsItsDraftAndReturnsToAnUnansweredStep() {
    let last = T3Question(id: "last", header: "Last", question: "Any notes?", options: [])
    var flow = T3QuestionFlow(request: .init(requestId: "id", questions: [singleQuestion, last]))
    flow.jump(to: 1)
    flow.setCustomAnswer("Keep this note")
    #expect(flow.confirm() == .needsAnswer)
    #expect(flow.index == 0)
    flow.select(singleQuestion.options[0])
    #expect(flow.confirm() == .advanced)
    #expect(flow.composerText == "Keep this note")
    #expect(flow.confirm() == .submit(["scope": .text("stale"), "last": .text("Keep this note")]))
}

@Test func newRequestsStartFreshEvenWhenQuestionIDsRepeat() {
    var previous = T3QuestionFlow(request: .init(requestId: "first", questions: [singleQuestion]))
    previous.select(singleQuestion.options[0])
    #expect(previous.confirm() == .submit(["scope": .text("stale")]))

    let next = T3QuestionFlow(request: .init(requestId: "next", questions: [singleQuestion]))
    #expect(!next.isSelected(singleQuestion.options[0]))
    #expect(!next.canAdvance)
    #expect(next.composerText.isEmpty)

    let seeded = T3Question(
        id: singleQuestion.id, header: "Notes", question: "Revise the proposed notes",
        options: singleQuestion.options, initialAnswer: "  Suggested notes\n"
    )
    let prefilled = T3QuestionFlow(request: .init(requestId: "seeded", questions: [seeded]))
    #expect(prefilled.composerText == "  Suggested notes\n")
    #expect(prefilled.canAdvance)
    #expect(!prefilled.isSelected(singleQuestion.options[0]))
}
