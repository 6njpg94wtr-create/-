import Foundation

public enum ExerciseGrader {
    public static func grade(_ question: ExerciseQuestion, answer: String) throws -> ExerciseGrade {
        try question.validate()
        switch question.type {
        case .multipleChoice:
            guard question.options.contains(where: { $0.id == answer }) else { throw ExerciseError.invalidOption }
            return ExerciseGrade(isCorrect: answer == question.correctAnswer, usedYoEquivalence: false)
        case .textInput:
            let user = normalize(answer, policy: question.inputPolicy)
            let expected = normalize(question.correctAnswer, policy: question.inputPolicy)
            if user == expected { return ExerciseGrade(isCorrect: true, usedYoEquivalence: false) }
            let loose = question.inputPolicy.yoMatching == .equivalent && user.replacingOccurrences(of: "ё", with: "е") == expected.replacingOccurrences(of: "ё", with: "е")
            return ExerciseGrade(isCorrect: loose, usedYoEquivalence: loose)
        }
    }

    private static func normalize(_ text: String, policy: InputAnswerPolicy) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().decomposedStringWithCanonicalMapping
        if policy.ignoreStress { value = value.replacingOccurrences(of: "\u{0301}", with: "") }
        // Recompose ё and й; never strip all combining marks as dictionary search might.
        return value.precomposedStringWithCanonicalMapping
    }
}
