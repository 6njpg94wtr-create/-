import Foundation
import XCTest
@testable import RussianWordsCore

final class DictionaryRepositoryTests: XCTestCase {
    private var databaseURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/dictionary.sqlite")
    }

    private func repository() throws -> DictionaryRepository {
        try DictionaryRepository(url: databaseURL)
    }

    func testFavoritesScopeCannotFallBackToAllEntries() async throws {
        let database = try repository()
        for text in ["", "такси"] {
            do {
                _ = try await database.search(text, scope: .favorites)
                XCTFail("Favorites require user IDs and must not return the full dictionary")
            } catch DictionaryError.favoritesRequireUserState {
                // The AppModel owns this scope and resolves only saved IDs.
            }
        }
    }

    func testFavoriteIDsResolveOnlySavedEntriesAndRemovalSurvivesRestart() async throws {
        let database = try repository()
        let entries = try await database.search("", scope: .all, limit: 2)
        XCTAssertEqual(entries.count, 2)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let store = try LearningStateRepository(storageURL: url, legacyDefaults: nil)
        try store.setFavorite(entryID: entries[0].id, isFavorite: true)
        try store.setFavorite(entryID: entries[0].id, isFavorite: true)
        let restarted = try LearningStateRepository(storageURL: url, legacyDefaults: nil)
        let favorites = try await database.entries(ids: restarted.state.favorites.sorted())
        XCTAssertEqual(favorites.map(\.id), [entries[0].id])
        XCTAssertFalse(favorites.contains { $0.id == entries[1].id })
        try restarted.setFavorite(entryID: entries[0].id, isFavorite: false)
        let reopened = try LearningStateRepository(storageURL: url, legacyDefaults: nil)
        let removed = try await database.entries(ids: reopened.state.favorites.sorted())
        XCTAssertTrue(removed.isEmpty)
    }

    func testPinnedRealDictionaryCountAndHonestTeachingCoverage() async throws {
        let database = try repository()
        let stats = try await database.stats()
        XCTAssertEqual(stats.total, 45_697)
        XCTAssertGreaterThan(stats.total, 30_000)
        XCTAssertEqual(stats.core, 0)
        XCTAssertEqual(stats.basic, 0)
        XCTAssertEqual(stats.chinese, 0)
        XCTAssertEqual(stats.verified, 0)
        let candidates = try await database.learningCandidates()
        XCTAssertTrue(candidates.isEmpty)
    }

    func testRussianSearchIgnoresStressAndCase() async throws {
        let database = try repository()
        let plain = try await database.search("спасибо", scope: .all)
        let stressed = try await database.search("  СПАСИ\u{0301}БО  ", scope: .all)
        XCTAssertFalse(plain.isEmpty)
        XCTAssertTrue(plain.contains { $0.russian == "спасибо" })
        XCTAssertEqual(plain.map(\.id), stressed.map(\.id))
    }

    func testYoSearchEquivalenceKeepsOriginalDisplaySpelling() async throws {
        let database = try repository()
        let withYo = try await database.search("ёлка", scope: .all)
        let withYe = try await database.search("елка", scope: .all)
        let decomposed = try await database.search("е\u{0308}лка", scope: .all)
        XCTAssertTrue(withYo.contains { $0.russian == "ёлка" })
        XCTAssertEqual(withYo.map(\.id), withYe.map(\.id))
        XCTAssertEqual(withYo.map(\.id), decomposed.map(\.id))
    }

    func testInflectedFormFindsLemma() async throws {
        let database = try repository()
        let people = try await database.search("людей", scope: .all)
        let past = try await database.search("был", scope: .all)
        let school = try await database.search("школе", scope: .all)
        XCTAssertTrue(people.contains { $0.russian == "человек" })
        XCTAssertTrue(past.contains { $0.russian == "быть" })
        XCTAssertTrue(school.contains { $0.russian == "школа" })
        for (form, lemma) in [("книги", "книга"), ("говорю", "говорить"), ("читаешь", "читать")] {
            let matches = try await database.search(form, scope: .all)
            XCTAssertTrue(matches.contains { $0.russian == lemma }, "\(form) should resolve to \(lemma)")
        }
    }

    func testInflectedSearchNormalizationPreservesStoredSpelling() async throws {
        let database = try repository()
        for (plain, normalizedVariant, lemma) in [
            ("школе", "  ШКО\u{0301}ЛЕ  ", "школа"),
            ("говорю", "ГОВОРЮ\u{0301}", "говорить"),
            ("ёлки", "е\u{0308}лки", "ёлка"),
            ("ёлки", "Е\u{0301}ЛКИ", "ёлка")
        ] {
            let baseline = try await database.search(plain, scope: .all)
            let variant = try await database.search(normalizedVariant, scope: .all)
            XCTAssertTrue(baseline.contains { $0.russian == lemma })
            XCTAssertEqual(baseline.map(\.id), variant.map(\.id))
            XCTAssertEqual(baseline, variant, "Normalization must not change returned Russian spelling or stress")
            let stored = try await database.entries(ids: baseline.map(\.id))
            XCTAssertEqual(stored, baseline, "Search results must preserve the stored entries")
        }
    }

    func testTeachingScopesDoNotRelabelReferenceEntries() async throws {
        let database = try repository()
        let core = try await database.search("", scope: .core)
        let basic = try await database.search("", scope: .basic)
        let reference = try await database.search("такси", scope: .reference)
        let chinese = try await database.search("出租车", scope: .all)
        XCTAssertTrue(core.isEmpty)
        XCTAssertTrue(basic.isEmpty)
        XCTAssertTrue(chinese.isEmpty)
        XCTAssertTrue(reference.contains { $0.russian == "такси" && $0.english == "taxi" })
        XCTAssertTrue(reference.allSatisfy { $0.tier == 3 && $0.chinese.isEmpty && $0.reviewStatus == "pending" })
    }

    func testEnglishSubstringSearchFindsActualDefinition() async throws {
        let database = try repository()
        let matches = try await database.search("christmas tree", scope: .all)
        XCTAssertTrue(matches.contains { $0.russian == "ёлка" })
    }

    func testSQLAndLikeCharactersRemainLiteral() async throws {
        let database = try repository()
        for term in ["%", "_", "\\"] {
            let matches = try await database.search(term, scope: .all, limit: 500)
            XCTAssertTrue(matches.allSatisfy {
                RussianSearch.normalize($0.russian).contains(term) || $0.english.lowercased().contains(term) || $0.chinese.contains(term)
            }, "LIKE metacharacter must be searched literally: \(term)")
        }
        let injection = try await database.search("' OR 1=1 --", scope: .all)
        XCTAssertTrue(injection.isEmpty)
        let stats = try await database.stats()
        XCTAssertEqual(stats.total, 45_697)
    }

    func testSearchLimitsAndDeduplication() async throws {
        let database = try repository()
        let entries = try await database.search("а", scope: .all, limit: 200)
        XCTAssertEqual(entries.count, 200)
        XCTAssertEqual(entries.count, Set(entries.map(\.id)).count)
        let bounded = try await database.search("", scope: .all, limit: 10_000)
        XCTAssertEqual(bounded.count, 500)
    }

    func testBatchedIDLookupPreservesRequestedOrder() async throws {
        let database = try repository()
        let entries = try await database.search("", scope: .all, limit: 450)
        let ids = entries.map(\.id).reversed().map { $0 }
        let fetched = try await database.entries(ids: ids)
        XCTAssertEqual(fetched.map(\.id), ids)
        let empty = try await database.entries(ids: [])
        XCTAssertTrue(empty.isEmpty)
    }

    func testMissingDatabaseDoesNotCreateEmptyFile() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        XCTAssertThrowsError(try DictionaryRepository(url: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }
}
