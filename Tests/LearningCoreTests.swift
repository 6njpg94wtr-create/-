import Foundation
import XCTest
@testable import RussianWordsCore

final class LearningCoreTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private var defaultsName: String!
    private let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaultsName = "RussianWordsCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: folder)
    }

    private func repository() throws -> LearningStateRepository {
        try LearningStateRepository(storageURL: folder.appendingPathComponent("progress.json"), legacyDefaults: defaults, calendar: calendar, now: instant)
    }

    private func candidate(_ id: String, tier: LearningTier = .core, chinese: Bool = true, reviewed: Bool = true, rank: Int? = nil) -> LearningCandidate {
        LearningCandidate(id: id, tier: tier, hasChinese: chinese, isReviewed: reviewed, frequencyRank: rank)
    }

    func testCoreIsSubsetOfBasicNotAdditionalThousand() {
        XCTAssertEqual(LearningTier.core.targetCount, 1_000)
        XCTAssertEqual(LearningTier.basic.targetCount, 3_000)
        XCTAssertTrue(LearningTier.basic.includes(.core))
        XCTAssertTrue(LearningTier.basic.includes(.basic))
        XCTAssertFalse(LearningTier.basic.includes(.reference))
        XCTAssertFalse(LearningTier.core.includes(.basic))
    }

    func testOnlyReviewedChineseLearningEntriesAreAutomaticallySelected() throws {
        let store = try repository()
        let items = [candidate("query", tier: .reference), candidate("unreviewed", reviewed: false),
                     candidate("noChinese", chinese: false), candidate("basic", tier: .basic, rank: 1),
                     candidate("core", rank: 200), candidate("core", rank: 200), candidate("", rank: 1)]
        XCTAssertEqual(store.newEntryIDs(from: items, at: instant), ["core", "basic"])
    }

    func testNewWordDailyLimitPersistsAndRepeatedAnswersDoNotConsumeItTwice() throws {
        let store = try repository()
        try store.setDailyGoal(2)
        try store.review(entryID: "first", rating: .again, now: instant)
        try store.review(entryID: "first", rating: .good, now: instant.addingTimeInterval(60))
        XCTAssertEqual(store.todayReviewCount(at: instant), 2)
        XCTAssertEqual(store.todayNewCount(at: instant), 1)
        XCTAssertEqual(store.todayAccuracy(at: instant), 0.5)
        let reopened = try repository()
        XCTAssertEqual(reopened.newEntryIDs(from: [candidate("first"), candidate("second"), candidate("third")], at: instant), ["second"])
    }

    func testSM2IntervalsAndFailureReset() {
        var record = ReviewRecord(entryID: "word", dueDate: instant)
        record = record.applying(.good, at: instant, calendar: calendar)
        XCTAssertEqual(record.intervalDays, 1)
        XCTAssertEqual(record.repetitions, 1)
        record = record.applying(.good, at: record.dueDate, calendar: calendar)
        XCTAssertEqual(record.intervalDays, 6)
        record = record.applying(.good, at: record.dueDate, calendar: calendar)
        XCTAssertEqual(record.intervalDays, 15)
        record = record.applying(.again, at: record.dueDate, calendar: calendar)
        XCTAssertEqual(record.repetitions, 0)
        XCTAssertEqual(record.intervalDays, 1)
        XCTAssertEqual(record.lapseCount, 1)
        XCTAssertEqual(record.reviewCount, 4)
        XCTAssertEqual(record.easeFactor, 1.7, accuracy: 0.0001)
    }

    func testSM2EaseFactorLowerBoundAndButtonMapping() {
        XCTAssertEqual(ReviewRating.hard.quality, 3)
        XCTAssertEqual(ReviewRating.good.quality, 4)
        XCTAssertEqual(ReviewRating.easy.quality, 5)
        var record = ReviewRecord(entryID: "word", dueDate: instant)
        for _ in 0..<20 { record = record.applying(.again, at: instant, calendar: calendar) }
        XCTAssertEqual(record.easeFactor, 1.3)
        XCTAssertEqual(record.lapseCount, 20)
    }

    func testDueQueueIncludesExplicitReferenceEnrollmentOnly() throws {
        let store = try repository()
        XCTAssertTrue(store.newEntryIDs(from: [candidate("reference", tier: .reference)], at: instant).isEmpty)
        try store.enroll(entryID: "reference", now: instant)
        XCTAssertEqual(store.dueEntryIDs(at: instant), ["reference"])
        try store.review(entryID: "reference", rating: .good, now: instant)
        XCTAssertTrue(store.dueEntryIDs(at: instant).isEmpty)
        XCTAssertEqual(store.dueEntryIDs(at: instant.addingTimeInterval(86_400)), ["reference"])
    }

    func testFavoritesGoalsAndRecordsSurviveRestart() throws {
        let store = try repository()
        try store.setFavorite(entryID: "word", isFavorite: true)
        try store.setDailyGoal(20)
        try store.review(entryID: "word", rating: .easy, now: instant)
        let restarted = try repository()
        XCTAssertEqual(restarted.state, store.state)
        XCTAssertTrue(restarted.state.favorites.contains("word"))
        XCTAssertEqual(restarted.state.dailyGoal, 20)
    }

    func testLegacyMigrationPreservesOriginalDataAndMasteryWithoutInventingStudyDays() throws {
        let word = LegacyLearningWord(russian: "слово", phonetic: "", chinese: "词", category: "我的单词", isMastered: true)
        let data = try JSONEncoder().encode([word])
        defaults.set(data, forKey: LearningStateRepository.legacyKey)
        let store = try repository()
        XCTAssertEqual(store.state.legacyWords, [word])
        XCTAssertEqual(store.state.records[word.entryID]?.repetitions, 3)
        XCTAssertEqual(store.state.records[word.entryID]?.reviewCount, 0)
        XCTAssertEqual(store.streak(at: instant), 0)
        XCTAssertEqual(store.todayReviewCount(at: instant), 0)
        XCTAssertEqual(defaults.data(forKey: LearningStateRepository.legacyKey), data)
        try store.review(entryID: word.entryID, rating: .good, now: instant)
        XCTAssertEqual(store.todayNewCount(at: instant), 0)
        let reopened = try repository()
        XCTAssertEqual(reopened.state.legacyWords.count, 1)
    }

    func testCorruptProgressFileIsNotOverwritten() throws {
        let bytes = Data("broken JSON".utf8)
        let path = folder.appendingPathComponent("progress.json")
        try bytes.write(to: path)
        XCTAssertThrowsError(try repository())
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }

    func testCorruptLegacyDataDoesNotCreateProgressFileOrEraseOldKey() throws {
        let bytes = Data("broken legacy data".utf8)
        defaults.set(bytes, forKey: LearningStateRepository.legacyKey)
        XCTAssertThrowsError(try repository())
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("progress.json").path))
        XCTAssertEqual(defaults.data(forKey: LearningStateRepository.legacyKey), bytes)
    }

    func testInvalidRestoreDoesNotChangeCurrentStateOrDisk() throws {
        let store = try repository()
        try store.setFavorite(entryID: "saved", isFavorite: true)
        let state = store.state
        let bytes = try Data(contentsOf: store.storageURL)
        XCTAssertThrowsError(try store.restore(from: Data("{}".utf8)))
        XCTAssertEqual(store.state, state)
        XCTAssertEqual(try Data(contentsOf: store.storageURL), bytes)
        var invalid = state
        invalid.schemaVersion = 999
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try store.restore(from: encoder.encode(invalid)))
        XCTAssertEqual(store.state, state)
    }

    func testBackupRestorePreservesPersonalContentAndProgress() throws {
        let store = try repository()
        let id = try store.addPersonalWord(russian: " дом ", chinese: " 房子 ")
        try store.setFavorite(entryID: id, isFavorite: true)
        try store.review(entryID: id, rating: .hard, now: instant)
        let other = try LearningStateRepository(storageURL: folder.appendingPathComponent("restored.json"), legacyDefaults: nil, calendar: calendar, now: instant)
        try other.restore(from: store.exportData())
        XCTAssertEqual(other.state, store.state)
    }

    func testPersonalWordAddEditAndDeletePreserveIdentityAndHistory() throws {
        let store = try repository()
        let id = try store.addPersonalWord(russian: " дом ", chinese: " 房子 ")
        XCTAssertEqual(try store.addPersonalWord(russian: "дом", chinese: "房子"), id)
        XCTAssertEqual(store.state.legacyWords.count, 1)
        XCTAssertTrue(store.newEntryIDs(from: [], at: instant).isEmpty)
        try store.updatePersonalWord(entryID: id, russian: "до́м", chinese: "家；房子", phonetic: "dom", category: "生活")
        XCTAssertEqual(store.state.legacyWords.first?.entryID, id)
        try store.review(entryID: id, rating: .good, now: instant)
        try store.setFavorite(entryID: id, isFavorite: true)
        let reopened = try repository()
        XCTAssertEqual(reopened.state.legacyWords.first?.chinese, "家；房子")
        try reopened.deletePersonalWord(entryID: id)
        XCTAssertTrue(reopened.state.legacyWords.isEmpty)
        XCTAssertNil(reopened.state.records[id])
        XCTAssertFalse(reopened.state.favorites.contains(id))
        XCTAssertEqual(reopened.todayReviewCount(at: instant), 1)
    }

    func testStreakHandlesYesterdayAndMissingDays() throws {
        let store = try repository()
        try store.review(entryID: "one", rating: .good, now: instant.addingTimeInterval(-86_400))
        XCTAssertEqual(store.streak(at: instant), 1)
        try store.review(entryID: "two", rating: .good, now: instant)
        XCTAssertEqual(store.streak(at: instant), 2)
        XCTAssertEqual(store.streak(at: instant.addingTimeInterval(86_400)), 2)
        XCTAssertEqual(store.streak(at: instant.addingTimeInterval(2 * 86_400)), 0)
    }

    func testInvalidInputsNeverChangeState() throws {
        let store = try repository()
        let state = store.state
        XCTAssertThrowsError(try store.setDailyGoal(0))
        XCTAssertThrowsError(try store.setDailyGoal(101))
        XCTAssertThrowsError(try store.review(entryID: " ", rating: .good, now: instant))
        XCTAssertThrowsError(try store.addPersonalWord(russian: "", chinese: "空"))
        XCTAssertEqual(store.state, state)
    }

    func testFailedSaveDoesNotMutateInMemoryState() throws {
        let nested = folder.appendingPathComponent("nested", isDirectory: true)
        let store = try LearningStateRepository(storageURL: nested.appendingPathComponent("progress.json"), legacyDefaults: nil)
        let state = store.state
        try FileManager.default.removeItem(at: nested)
        try Data("blocking file".utf8).write(to: nested)
        XCTAssertThrowsError(try store.setDailyGoal(30))
        XCTAssertEqual(store.state, state)
    }
}
