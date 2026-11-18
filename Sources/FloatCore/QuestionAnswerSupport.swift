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
