import Foundation
import XCTest
@testable import RussianWordsCore

final class ExerciseTests: XCTestCase {
    func testShippedExampleQuestionsGradeAndPersist() throws {
        XCTAssertEqual(ExampleExercises.questions.count, 2)
        let store = try store()
        for question in ExampleExercises.questions {
            try question.validate()
            XCTAssertFalse(question.relatedEntryID.isEmpty)
            XCTAssertTrue(try store.submit(question, answer: question.correctAnswer).isCorrect)
        }
        let choice = try XCTUnwrap(ExampleExercises.questions.first { $0.type == .multipleChoice })
        let wrong = try XCTUnwrap(choice.options.first { $0.id != choice.correctAnswer })
        XCTAssertFalse(try store.submit(choice, answer: wrong.id).isCorrect)
        let reopened = try ExerciseStore(storageURL: store.storageURL)
        XCTAssertEqual(reopened.totalAttempts, 3)
        XCTAssertEqual(reopened.correctAttempts, 2)
        XCTAssertEqual(reopened.mistakes[choice.questionID]?.userAnswer, wrong.id)
    }
    private let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private func input(policy: InputAnswerPolicy = InputAnswerPolicy(), correct: String = "ёлка") -> ExerciseQuestion {
        ExerciseQuestion(questionID: "test.input", type: .textInput, prompt: "测试输入题", correctAnswer: correct,
                         relatedEntryID: "test.entry", explanation: "测试答案说明", inputPolicy: policy)
    }
    private var choice: ExerciseQuestion {
        ExerciseQuestion(questionID: "test.choice", type: .multipleChoice, prompt: "选择测试答案", correctAnswer: "A",
                         options: [ExerciseOption(id: "A", text: "相同标签"), ExerciseOption(id: "B", text: "相同标签")], relatedEntryID: "test.entry")
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func store() throws -> ExerciseStore {
        try ExerciseStore(storageURL: folder().appendingPathComponent("exercise-progress.json"))
    }

    func testChoiceUsesOptionIDNotLabelOrCase() throws {
        XCTAssertTrue(try ExerciseGrader.grade(choice, answer: "A").isCorrect)
        XCTAssertFalse(try ExerciseGrader.grade(choice, answer: "B").isCorrect)
        XCTAssertThrowsError(try ExerciseGrader.grade(choice, answer: "相同标签"))
        XCTAssertThrowsError(try ExerciseGrader.grade(choice, answer: "a"))
    }

    func testInputCaseWhitespaceStressAndStrictYo() throws {
        for answer in ["  ЁЛКА\n", "ё\u{0301}лка", "е\u{0308}лка"] {
            let result = try ExerciseGrader.grade(input(), answer: answer)
            XCTAssertTrue(result.isCorrect)
            XCTAssertFalse(result.usedYoEquivalence)
        }
        for answer in ["елка", "ёл ка", "ёлка!", ""] { XCTAssertFalse(try ExerciseGrader.grade(input(), answer: answer).isCorrect) }
        XCTAssertFalse(try ExerciseGrader.grade(input(correct: "мой"), answer: "мои").isCorrect)
        XCTAssertTrue(try ExerciseGrader.grade(input(correct: "приве\u{0301}т"), answer: "Привет").isCorrect)
        XCTAssertFalse(try ExerciseGrader.grade(input(policy: InputAnswerPolicy(ignoreStress: false), correct: "приве\u{0301}т"), answer: "Привет").isCorrect)
    }

    func testLooseYoMustBeExplicitAndIsAuditedAfterRestart() throws {
        let store = try store()
        let question = input(policy: InputAnswerPolicy(yoMatching: .equivalent))
        let result = try store.submit(question, answer: "елка", now: instant)
        XCTAssertTrue(result.isCorrect)
        XCTAssertTrue(result.usedYoEquivalence)
        let reopened = try ExerciseStore(storageURL: store.storageURL)
        XCTAssertEqual(reopened.statistics[question.questionID]?.question.inputPolicy.yoMatching, .equivalent)
        XCTAssertEqual(reopened.statistics[question.questionID]?.lastGrade.usedYoEquivalence, true)
        XCTAssertTrue(reopened.mistakes.isEmpty)
    }

    func testWrongCountsAndLatestWrongAnswerSurviveCorrectAnswerAndRestart() throws {
        let store = try store(); let q = input()
        try store.submit(q, answer: "елка", now: instant)
        try store.submit(q, answer: "дом", now: instant.addingTimeInterval(1))
        let mistake = try XCTUnwrap(store.mistakes[q.questionID])
        XCTAssertEqual(mistake.questionID, q.questionID)
        XCTAssertEqual(mistake.relatedEntryID, q.relatedEntryID)
        XCTAssertEqual(mistake.userAnswer, "дом")
        XCTAssertEqual(mistake.correctAnswer, "ёлка")
        XCTAssertEqual(mistake.explanation, q.explanation)
        XCTAssertEqual(mistake.wrongCount, 2)
        XCTAssertEqual(mistake.lastWrongAt, instant.addingTimeInterval(1))
        try store.submit(q, answer: "ёлка", now: instant.addingTimeInterval(2))
        let reopened = try ExerciseStore(storageURL: store.storageURL)
        XCTAssertEqual(reopened.mistakes[q.questionID], mistake)
        XCTAssertEqual(reopened.statistics[q.questionID]?.attemptCount, 3)
        XCTAssertEqual(reopened.statistics[q.questionID]?.correctCount, 1)
        XCTAssertEqual(reopened.statistics[q.questionID]?.wrongCount, 2)
        XCTAssertEqual(reopened.statistics[q.questionID]?.lastGrade.isCorrect, true)
        XCTAssertEqual(try XCTUnwrap(reopened.accuracy), 1.0 / 3.0, accuracy: 0.0001)
    }

    func testPracticeDoesNotModifySM2MasteryFavoritesOrLearningCounters() throws {
        let learning = try LearningStateRepository(storageURL: folder().appendingPathComponent("progress.json"), legacyDefaults: nil, now: instant)
        try learning.setFavorite(entryID: "test.entry", isFavorite: true)
        try learning.enroll(entryID: "test.entry", now: instant)
        let original = try Data(contentsOf: learning.storageURL)
        let progress = learning.state
        let store = try ExerciseStore(learningStore: learning)
        XCTAssertEqual(store.storageURL.lastPathComponent, "exercise-progress.json")
        for i in 0..<5 { try store.submit(input(), answer: "ёлка", now: instant.addingTimeInterval(Double(i))) }
        try store.submit(choice, answer: "B", now: instant.addingTimeInterval(6))
        XCTAssertEqual(try Data(contentsOf: learning.storageURL), original)
        let reopened = try LearningStateRepository(storageURL: learning.storageURL, legacyDefaults: nil)
        XCTAssertEqual(reopened.state, progress)
        XCTAssertEqual(reopened.state.mastery(for: "test.entry"), .new)
        XCTAssertEqual(store.totalAttempts, 6)
        XCTAssertEqual(store.correctAttempts, 5)
    }

    func testInvalidQuestionsAndSelectionsDoNotCreateProgress() throws {
        let store = try store()
        let bad = ExerciseQuestion(questionID: "bad", type: .multipleChoice, prompt: "测试", correctAnswer: "missing",
                                   options: choice.options, relatedEntryID: "entry")
        XCTAssertThrowsError(try store.submit(bad, answer: "A"))
        let duplicate = ExerciseQuestion(questionID: "bad", type: .multipleChoice, prompt: "测试", correctAnswer: "A",
                                         options: [ExerciseOption(id: "A", text: "a"), ExerciseOption(id: "A", text: "b")], relatedEntryID: "entry")
        XCTAssertThrowsError(try store.submit(duplicate, answer: "A"))
        XCTAssertThrowsError(try store.submit(input(correct: " "), answer: "x"))
        XCTAssertThrowsError(try store.submit(choice, answer: "missing"))
        XCTAssertEqual(store.totalAttempts, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.storageURL.path))
    }

    func testReusingIDWithDifferentQuestionCannotMixStatistics() throws {
        let store = try store()
        try store.submit(input(), answer: "ёлка", now: instant)
        let bytes = try Data(contentsOf: store.storageURL)
        XCTAssertThrowsError(try store.submit(input(correct: "дом"), answer: "дом"))
        XCTAssertEqual(try Data(contentsOf: store.storageURL), bytes)
        XCTAssertEqual(store.totalAttempts, 1)
    }

    func testCorruptAndFutureFilesArePreserved() throws {
        let url = try folder().appendingPathComponent("exercise-progress.json")
        for data in [Data("broken".utf8), Data("{\"schemaVersion\":2,\"statistics\":{},\"mistakes\":{}}".utf8)] {
            try data.write(to: url)
            XCTAssertThrowsError(try ExerciseStore(storageURL: url))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testInvalidPersistedStatisticsAreRejectedWithoutOverwrite() throws {
        let store = try store()
        try store.submit(input(), answer: "дом", now: instant)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.storageURL)) as? [String: Any])
        var records = try XCTUnwrap(object["statistics"] as? [String: Any])
        var record = try XCTUnwrap(records["test.input"] as? [String: Any])
        record["correctCount"] = 9; records["test.input"] = record; object["statistics"] = records
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: store.storageURL)
        XCTAssertThrowsError(try ExerciseStore(storageURL: store.storageURL))
        XCTAssertEqual(try Data(contentsOf: store.storageURL), bytes)
    }

    func testFailedWriteDoesNotChangeInMemoryStatistics() throws {
        let base = try folder().appendingPathComponent("blocked")
        let store = try ExerciseStore(storageURL: base.appendingPathComponent("exercise-progress.json"))
        try Data("block directory".utf8).write(to: base)
        XCTAssertThrowsError(try store.submit(input(), answer: "дом"))
        XCTAssertTrue(store.statistics.isEmpty)
        XCTAssertTrue(store.mistakes.isEmpty)
    }
}
