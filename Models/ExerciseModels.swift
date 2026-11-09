import Foundation

public enum ExerciseType: String, Codable { case multipleChoice, textInput }
public enum YoMatching: String, Codable { case strict, equivalent }

public struct InputAnswerPolicy: Codable, Equatable {
    public let ignoreStress: Bool
    public let yoMatching: YoMatching
    public init(ignoreStress: Bool = true, yoMatching: YoMatching = .strict) {
        self.ignoreStress = ignoreStress; self.yoMatching = yoMatching
    }
}

public struct ExerciseOption: Codable, Equatable {
    public let id: String
    public let text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

public struct ExerciseQuestion: Codable, Equatable {
    public let questionID: String
    public let type: ExerciseType
    public let prompt: String
    /// An option ID for multiple choice; expected text for input questions.
    public let correctAnswer: String
    public let options: [ExerciseOption]
    public let relatedEntryID: String
    public let explanation: String?
    public let inputPolicy: InputAnswerPolicy

    public init(questionID: String, type: ExerciseType, prompt: String, correctAnswer: String,
                options: [ExerciseOption] = [], relatedEntryID: String, explanation: String? = nil,
                inputPolicy: InputAnswerPolicy = InputAnswerPolicy()) {
        self.questionID = questionID; self.type = type; self.prompt = prompt
        self.correctAnswer = correctAnswer; self.options = options; self.relatedEntryID = relatedEntryID
        self.explanation = explanation; self.inputPolicy = inputPolicy
    }

    public func validate() throws {
        guard [questionID, prompt, correctAnswer, relatedEntryID].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ExerciseError.invalidQuestion
        }
        switch type {
        case .multipleChoice:
            guard options.count >= 2, Set(options.map(\.id)).count == options.count,
                  options.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  options.contains(where: { $0.id == correctAnswer }) else { throw ExerciseError.invalidQuestion }
        case .textInput:
            guard options.isEmpty else { throw ExerciseError.invalidQuestion }
        }
    }
}

public struct ExerciseGrade: Codable, Equatable {
    public let isCorrect: Bool
    /// True only if the answer would be wrong under strict ё/e comparison.
    public let usedYoEquivalence: Bool
}

public struct QuestionPracticeRecord: Codable, Equatable {
    public let question: ExerciseQuestion
    public var attemptCount: Int
    public var correctCount: Int
    public var wrongCount: Int
    public var lastAttemptAt: Date
    public var lastUserAnswer: String
    public var lastGrade: ExerciseGrade
}

public struct ExerciseMistake: Codable, Equatable {
    public let questionID: String
    public let relatedEntryID: String
    public var userAnswer: String
    public let correctAnswer: String
    public var wrongCount: Int
    public var lastWrongAt: Date
    public let explanation: String?
    public let inputPolicy: InputAnswerPolicy
}

public enum ExerciseError: LocalizedError {
    case invalidQuestion, invalidOption, changedQuestion, invalidProgress, unsupportedVersion(Int), attemptLimit
    public var errorDescription: String? {
        switch self {
        case .invalidQuestion: return "练习题目字段、答案或选项无效。"
        case .invalidOption: return "请选择题目提供的选项。"
        case .changedQuestion: return "相同题目 ID 的内容已改变，请为修订题目使用新的 ID。"
        case .invalidProgress: return "练习记录无效，原文件已保留。"
        case .unsupportedVersion(let version): return "暂不支持练习记录版本 \(version)，原文件已保留。"
        case .attemptLimit: return "该题练习次数已超出支持范围。"
        }
    }
}
