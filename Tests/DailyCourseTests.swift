import Foundation
import XCTest
@testable import RussianWordsCore

final class DailyCourseTests: XCTestCase {
    func testShippedDayOneCanCompleteAndRestore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let loader = try JSONCourseLoader(url: root.appendingPathComponent("Resources/day1.sample.json"))
        let course = try XCTUnwrap(loader.course(dayNumber: 1))
        let path = try directory().appendingPathComponent("course-progress.json")
        let store = try CourseProgressStore(storageURL: path)
        for task in CourseTaskKind.allCases where course.requiredTasks.contains(task) {
            try store.setTask(task, completed: true, for: course)
        }
        XCTAssertEqual(try CourseProgressStore(storageURL: path).status(for: course).completionState, .completed)
        XCTAssertEqual(loader.availableDays, [1])
    }
    private func entry(day: Int = 1, revision: Int = 1, allTasks: Bool = true) -> [String: Any] {
        ["id": "test.lesson", "revision": revision, "dayNumber": day, "title": "测试课程", "learningGoal": "验证课程结构",
         "vocabularyIDs": allTasks ? ["test.word"] : [], "reviewIDs": allTasks ? ["test.review"] : [],
         "grammarTopic": "测试语法", "grammarExplanation": "测试讲解",
         "exampleSentences": [["id": "test.example", "russian": "Приве́т!", "chinese": "你好！"]],
         "estimatedMinutes": 5, "isSample": true]
    }
    private func loader(_ entries: [[String: Any]], version: Int = 1) throws -> JSONCourseLoader {
        try JSONCourseLoader(data: JSONSerialization.data(withJSONObject: ["schemaVersion": version, "courses": entries]))
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testOnlyOneBundledSampleExistsAndMissingDaysStayMissing() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONCourseLoader(url: root.appendingPathComponent("Resources/day1.sample.json"))
        XCTAssertEqual(catalog.availableDays, [1])
        let sample = try XCTUnwrap(catalog.course(dayNumber: 1))
        XCTAssertTrue(sample.isSample)
        XCTAssertTrue(sample.vocabularyIDs.isEmpty)
        XCTAssertTrue(sample.reviewIDs.isEmpty)
        XCTAssertEqual(sample.requiredTasks, [.grammar, .examples])
        XCTAssertNil(try catalog.course(dayNumber: 2))
        XCTAssertNil(try catalog.course(dayNumber: 90))
    }

    func testNinetyDayRangeAndDuplicateValidation() throws {
        XCTAssertEqual(try loader([entry(day: 90)]).availableDays, [90])
        for day in [0, 91] { XCTAssertThrowsError(try loader([entry(day: day)])) }
        XCTAssertThrowsError(try loader([entry(), entry()]))
        XCTAssertThrowsError(try loader([entry(), entry(day: 2)])) // duplicate stable ID
        var duplicateDay = entry(); duplicateDay["id"] = "other.lesson"
        XCTAssertThrowsError(try loader([entry(), duplicateDay]))
        XCTAssertThrowsError(try loader([entry()], version: 2))
        XCTAssertThrowsError(try loader([entry(revision: 0)]))
        let catalog = try loader([entry()])
        XCTAssertThrowsError(try catalog.course(dayNumber: 91))
    }

    func testFourTaskTypesCompletionReopeningAndLearningCompatibility() throws {
        let folder = try directory()
        let learning = try LearningStateRepository(storageURL: folder.appendingPathComponent("progress.json"), legacyDefaults: nil)
        try learning.setFavorite(entryID: "existing.word", isFavorite: true)
        for _ in 0..<3 {
            // The existing progress wire format uses whole-second ISO 8601 dates.
            try learning.review(entryID: "existing.word", rating: .good, now: learning.state.records["existing.word"]?.dueDate ?? Date(timeIntervalSince1970: 1_700_000_000))
        }
        let previous = learning.state
        let originalBytes = try Data(contentsOf: learning.storageURL)
        let course = try XCTUnwrap(loader([entry()]).course(dayNumber: 1))
        let store = try CourseProgressStore(learningStore: learning)
        XCTAssertEqual(store.storageURL.lastPathComponent, "course-progress.json")
        XCTAssertEqual(try store.status(for: course).completionState, .notStarted)
        try store.setTask(.newVocabulary, completed: true, for: course)
        XCTAssertEqual(try store.status(for: course).completionState, .inProgress)
        for task in [CourseTaskKind.review, .grammar, .examples] { try store.setTask(task, completed: true, for: course) }
        let reopened = try CourseProgressStore(learningStore: learning)
        let status = try reopened.status(for: course)
        XCTAssertEqual(status.completionState, .completed)
        for task in CourseTaskKind.allCases { XCTAssertEqual(status.state(for: task), .completed) }
        try reopened.setTask(.grammar, completed: false, for: course)
        XCTAssertEqual(try CourseProgressStore(learningStore: learning).status(for: course).completionState, .inProgress)
        XCTAssertEqual(try Data(contentsOf: learning.storageURL), originalBytes)
        XCTAssertEqual(try LearningStateRepository(storageURL: learning.storageURL, legacyDefaults: nil).state, previous)
        XCTAssertEqual(previous.mastery(for: "existing.word"), .mastered)
    }

    func testAbsentTasksAreNotApplicableAndCannotBeCompleted() throws {
        let store = try CourseProgressStore(storageURL: directory().appendingPathComponent("course-progress.json"))
        let course = try XCTUnwrap(loader([entry(allTasks: false)]).course(dayNumber: 1))
        XCTAssertEqual(try store.status(for: course).state(for: .newVocabulary), .notApplicable)
        XCTAssertEqual(try store.status(for: course).state(for: .review), .notApplicable)
        XCTAssertThrowsError(try store.setTask(.newVocabulary, completed: true, for: course))
        try store.setTask(.grammar, completed: true, for: course)
        XCTAssertEqual(try store.status(for: course).completionState, .inProgress)
        try store.setTask(.examples, completed: true, for: course)
        XCTAssertEqual(try store.status(for: course).completionState, .completed)
    }

    func testContentRevisionDoesNotInheritOldCompletion() throws {
        let store = try CourseProgressStore(storageURL: directory().appendingPathComponent("course-progress.json"))
        let first = try XCTUnwrap(loader([entry()]).course(dayNumber: 1))
        try store.setTask(.grammar, completed: true, for: first)
        let second = try XCTUnwrap(loader([entry(revision: 2)]).course(dayNumber: 1))
        XCTAssertEqual(try store.status(for: second).completionState, .notStarted)
        XCTAssertEqual(try store.status(for: first).state(for: .grammar), .completed)
    }

    func testCorruptOrFutureProgressIsNotOverwritten() throws {
        let url = try directory().appendingPathComponent("course-progress.json")
        for bytes in [Data("broken".utf8), Data("{\"schemaVersion\":2,\"records\":{}}".utf8)] {
            try bytes.write(to: url)
            XCTAssertThrowsError(try CourseProgressStore(storageURL: url))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testFailedSaveDoesNotMarkTaskCompleted() throws {
        let folder = try directory().appendingPathComponent("nested")
        let store = try CourseProgressStore(storageURL: folder.appendingPathComponent("course-progress.json"))
        let course = try XCTUnwrap(loader([entry()]).course(dayNumber: 1))
        try Data("block directory creation".utf8).write(to: folder)
        XCTAssertThrowsError(try store.setTask(.grammar, completed: true, for: course))
        XCTAssertEqual(try store.status(for: course).completionState, .notStarted)
    }

    func testIncompleteAndEmptyContentIsRejected() throws {
        var broken = entry(); broken["grammarExplanation"] = ""
        XCTAssertThrowsError(try loader([broken]))
        broken = entry(); broken["vocabularyIDs"] = ["id", "id"]
        XCTAssertThrowsError(try loader([broken]))
        broken = entry(); broken["exampleSentences"] = [["id": "x", "russian": "Привет", "chinese": ""]]
        XCTAssertThrowsError(try loader([broken]))
        broken = entry(allTasks: false); broken["grammarTopic"] = ""; broken["grammarExplanation"] = ""; broken["exampleSentences"] = []
        XCTAssertThrowsError(try loader([broken]))
    }
}
