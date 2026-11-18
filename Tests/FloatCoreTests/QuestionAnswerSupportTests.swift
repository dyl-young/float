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
