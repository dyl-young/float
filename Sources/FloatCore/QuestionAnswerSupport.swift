import Foundation

extension T3Question.Option {
    public var displayDescription: String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalizedForComparison(text)
        guard !normalized.isEmpty, !Self.normalizedForComparison(label).hasPrefix(normalized) else {
            return nil
        }
        return text
    }

    private static func normalizedForComparison(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = normalized.last, last.isPunctuation || last.isWhitespace {
            normalized.removeLast()
        }
        return normalized
    }
}

public enum T3QuestionAnswer: Equatable, Sendable {
    case text(String)
    case selections([String])

    var argument: any Sendable {
        switch self {
        case .text(let value): value
        case .selections(let values): values
        }
    }
}

public enum T3QuestionAnswerBuilder {
    public static func resolve(
        _ question: T3Question, draft: T3QuestionDraft?
    ) -> T3QuestionAnswer? {
        if question.allowsCustom {
            if question.initialAnswer != nil, let custom = draft?.customAnswer {
                return .text(custom)
            }
            if let custom = draft?.customAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
                !custom.isEmpty {
                return .text(custom)
            }
        }
        if !question.isRequired, question.options.isEmpty {
            return .text("")
        }

        var selected: [String] = []
        for candidate in draft?.selectedOptionValues ?? [] {
            let resolved: String?
            if question.options.contains(where: { $0.value == candidate }) {
                resolved = candidate
            } else {
                let label = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                resolved = question.options.contains(where: {
                    $0.value == nil
                        && $0.label.trimmingCharacters(in: .whitespacesAndNewlines) == label
                }) ? label : nil
            }
            if let resolved, !selected.contains(resolved) {
                selected.append(resolved)
            }
        }
        if question.allowsMultiple {
            return selected.isEmpty ? nil : .selections(selected)
        }
        return selected.first.map(T3QuestionAnswer.text)
    }

    public static func build(
        questions: [T3Question], drafts: [String: T3QuestionDraft]
    ) -> [String: T3QuestionAnswer]? {
        var answers: [String: T3QuestionAnswer] = [:]
        for question in questions {
            guard let answer = resolve(question, draft: drafts[question.id]) else { return nil }
            answers[question.id] = answer
        }
        return answers
    }
}

public struct T3QuestionFlow: Sendable {
    public enum Confirmation: Equatable, Sendable {
        case advanced
        case submit([String: T3QuestionAnswer])
    }

    public let request: T3PendingQuestionRequest
    public private(set) var index = 0
    public private(set) var drafts: [String: T3QuestionDraft]

    public init(request: T3PendingQuestionRequest) {
        self.request = request
        drafts = Dictionary(uniqueKeysWithValues: request.questions.map {
            ($0.id, T3QuestionDraft(customAnswer: $0.allowsCustom ? $0.initialAnswer : nil))
        })
    }

    public var activeQuestion: T3Question? {
        request.questions.indices.contains(index) ? request.questions[index] : nil
    }

    public var isLast: Bool { index >= request.questions.count - 1 }

    private var activeDraft: T3QuestionDraft? {
        activeQuestion.flatMap { drafts[$0.id] }
    }

    public var canAdvance: Bool {
        guard let question = activeQuestion else { return false }
        return T3QuestionAnswerBuilder.resolve(question, draft: activeDraft) != nil
    }

    public var composerText: String {
        guard activeQuestion?.allowsCustom == true else { return "" }
        return activeDraft?.customAnswer ?? ""
    }

    public func isSelected(_ option: T3Question.Option) -> Bool {
        activeDraft?.selectedOptionValues.contains(option.answerValue) == true
    }

    public mutating func select(_ option: T3Question.Option) {
        guard let question = activeQuestion, question.options.contains(option) else { return }
        var draft = drafts[question.id] ?? T3QuestionDraft()
        let value = option.answerValue
        if !question.allowsMultiple {
            draft.selectedOptionValues = [value]
        } else if let index = draft.selectedOptionValues.firstIndex(of: value) {
            draft.selectedOptionValues.remove(at: index)
        } else {
            draft.selectedOptionValues.append(value)
        }
        draft.customAnswer = ""
        drafts[question.id] = draft
    }

    public mutating func setCustomAnswer(_ text: String) {
        guard let question = activeQuestion, question.allowsCustom else { return }
        var draft = drafts[question.id] ?? T3QuestionDraft()
        draft.customAnswer = text
        if question.initialAnswer != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.selectedOptionValues = []
        }
        drafts[question.id] = draft
    }

    public mutating func goBack() -> Bool {
        guard index > 0 else { return false }
        index -= 1
        return true
    }

    public mutating func confirm() -> Confirmation? {
        guard canAdvance else { return nil }
        if isLast {
            return T3QuestionAnswerBuilder.build(questions: request.questions, drafts: drafts)
                .map(Confirmation.submit)
        }
        index += 1
        return .advanced
    }
}
