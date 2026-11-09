import Foundation

/// Serialized use, like LearningStateRepository. Objective practice records are
/// independent of SM-2 ratings, mastery, favorites and course task checkmarks.
public final class ExerciseStore {
    private struct Document: Codable {
        var schemaVersion = 1
        var statistics: [String: QuestionPracticeRecord] = [:]
        var mistakes: [String: ExerciseMistake] = [:]
    }
    private var document: Document
    public let storageURL: URL
    public var statistics: [String: QuestionPracticeRecord] { document.statistics }
    public var mistakes: [String: ExerciseMistake] { document.mistakes }
    public var totalAttempts: Int { document.statistics.values.reduce(0) { $0 + $1.attemptCount } }
    public var correctAttempts: Int { document.statistics.values.reduce(0) { $0 + $1.correctCount } }
    public var accuracy: Double? { totalAttempts == 0 ? nil : Double(correctAttempts) / Double(totalAttempts) }

    public convenience init(learningStore: LearningStateRepository) throws {
        try self.init(storageURL: learningStore.storageURL.deletingLastPathComponent().appendingPathComponent("exercise-progress.json"))
    }

    public init(storageURL: URL) throws {
        self.storageURL = storageURL
        if FileManager.default.fileExists(atPath: storageURL.path) {
            document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: storageURL))
            try Self.validate(document)
        } else { document = Document() }
    }

    @discardableResult
    public func submit(_ question: ExerciseQuestion, answer: String, now: Date = Date()) throws -> ExerciseGrade {
        let grade = try ExerciseGrader.grade(question, answer: answer)
        if let prior = document.statistics[question.questionID], prior.question != question { throw ExerciseError.changedQuestion }
        guard now.timeIntervalSince1970.isFinite else { throw ExerciseError.invalidProgress }
        var next = document
        var record = next.statistics[question.questionID] ?? QuestionPracticeRecord(
            question: question, attemptCount: 0, correctCount: 0, wrongCount: 0,
            lastAttemptAt: now, lastUserAnswer: answer, lastGrade: grade)
        guard record.attemptCount < 1_000_000 else { throw ExerciseError.attemptLimit }
        record.attemptCount += 1
        if grade.isCorrect { record.correctCount += 1 } else { record.wrongCount += 1 }
        record.lastAttemptAt = now; record.lastUserAnswer = answer; record.lastGrade = grade
        next.statistics[question.questionID] = record
        if !grade.isCorrect {
            next.mistakes[question.questionID] = ExerciseMistake(
                questionID: question.questionID, relatedEntryID: question.relatedEntryID,
                userAnswer: answer, correctAnswer: question.correctAnswer, wrongCount: record.wrongCount,
                lastWrongAt: now, explanation: question.explanation, inputPolicy: question.inputPolicy)
        }
        try Self.validate(next)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(next)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
        document = next
        return grade
    }

    private static func validate(_ value: Document) throws {
        guard value.schemaVersion == 1 else { throw ExerciseError.unsupportedVersion(value.schemaVersion) }
        for (id, record) in value.statistics {
            try record.question.validate()
            guard id == record.question.questionID, (1...1_000_000).contains(record.attemptCount),
                  (0...record.attemptCount).contains(record.correctCount),
                  record.wrongCount == record.attemptCount - record.correctCount,
                  record.lastAttemptAt.timeIntervalSince1970.isFinite,
                  try ExerciseGrader.grade(record.question, answer: record.lastUserAnswer) == record.lastGrade else { throw ExerciseError.invalidProgress }
            guard (record.wrongCount > 0) == (value.mistakes[id] != nil) else { throw ExerciseError.invalidProgress }
        }
        for (id, mistake) in value.mistakes {
            guard let record = value.statistics[id], id == mistake.questionID,
                  mistake.relatedEntryID == record.question.relatedEntryID,
                  mistake.correctAnswer == record.question.correctAnswer, mistake.wrongCount == record.wrongCount,
                  mistake.inputPolicy == record.question.inputPolicy, mistake.explanation == record.question.explanation,
                  mistake.lastWrongAt.timeIntervalSince1970.isFinite,
                  mistake.lastWrongAt <= record.lastAttemptAt,
                  try !ExerciseGrader.grade(record.question, answer: mistake.userAnswer).isCorrect else { throw ExerciseError.invalidProgress }
        }
    }
}
