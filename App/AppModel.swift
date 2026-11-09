import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var results: [DictionaryEntry] = []
    @Published var searchText = ""
    @Published var selectedScope: LibraryScope = .all
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showStress = UserDefaults.standard.object(forKey: "showStress") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showStress, forKey: "showStress") }
    }
    @Published var stats = DictionaryStats()
    @Published var dailyGoal = 10
    @Published var todayCount = 0
    @Published var streak = 0
    @Published var dueCount = 0
    @Published var reviewEntries: [DictionaryEntry] = []
    @Published var favorites: [DictionaryEntry] = []
    @Published var personalWords: [LegacyLearningWord] = []
    @Published var legacyCount = 0
    @Published private var revision = 0
    private var learning: LearningStateRepository?
    private var dictionary: DictionaryRepository?
    private var candidates: [LearningCandidate] = []
    private var searchTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var favoritesTask: Task<Void, Never>?

    init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            learning = try LearningStateRepository(storageURL: directory.appendingPathComponent("RussianWords/progress.json"))
            refreshProgress()
        } catch { errorMessage = error.localizedDescription }
        do {
            guard let url = Bundle.main.url(forResource: "dictionary", withExtension: "sqlite") else { throw DictionaryError.missing }
            dictionary = try DictionaryRepository(url: url)
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() {
        refreshProgress()
        Task {
            do {
                if let dictionary {
                    stats = try await dictionary.stats()
                    candidates = try await dictionary.learningCandidates()
                }
                loadFavorites()
                search()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func search() {
        searchTask?.cancel()
        let text = searchText
        let scope = selectedScope
        isLoading = true
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                let found: [DictionaryEntry]
                if scope == .favorites {
                    let key = RussianSearch.normalize(text)
                    found = favorites.filter { key.isEmpty || RussianSearch.normalize($0.russian + " " + $0.translation).contains(key) }
                } else if let dictionary {
                    found = try await dictionary.search(text, scope: scope)
                } else { found = [] }
                try Task.checkCancellation()
                results = found
                isLoading = false
            } catch is CancellationError { /* newer search owns the loading state */ }
            catch { if !Task.isCancelled { errorMessage = error.localizedDescription; isLoading = false } }
        }
    }

    func isFavorite(_ id: String) -> Bool { learning?.state.favorites.contains(id) ?? false }
    func isEnrolled(_ id: String) -> Bool { learning?.state.records[id] != nil }

    func toggleFavorite(_ entry: DictionaryEntry) {
        modify { try $0.setFavorite(entryID: entry.id, isFavorite: !self.isFavorite(entry.id)) }
        loadFavorites()
    }

    func enroll(_ entry: DictionaryEntry) { modify { try $0.enroll(entryID: entry.id) } }

    func prepareReview() {
        reviewTask?.cancel()
        guard let learning else { return }
        let ids = learning.dueEntryIDs() + learning.newEntryIDs(from: candidates)
        reviewEntries = []
        reviewTask = Task {
            do {
                let entries = try await resolve(ids: ids)
                try Task.checkCancellation()
                reviewEntries = entries
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func rate(_ entry: DictionaryEntry, rating: ReviewRating) {
        guard let learning else { errorMessage = "学习记录尚未成功打开。"; return }
        do {
            try learning.review(entryID: entry.id, rating: rating)
            reviewEntries.removeAll { $0.id == entry.id }
            refreshProgress()
        } catch { errorMessage = error.localizedDescription }
    }

    func speak(_ text: String) { SpeechPlayback.shared.speak(text, language: "ru-RU") }
    func updateDailyGoal(_ goal: Int) { modify { try $0.setDailyGoal(goal) } }

    @discardableResult
    func addPersonalWord(russian: String, chinese: String, phonetic: String) -> Bool {
        guard let learning else { errorMessage = "学习记录尚未成功打开。"; return false }
        do {
            let id = try learning.addPersonalWord(russian: russian, chinese: chinese, phonetic: phonetic)
            try learning.enroll(entryID: id)
            refreshProgress()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func deletePersonalWord(_ word: LegacyLearningWord) {
        modify { try $0.deletePersonalWord(entryID: word.entryID) }
        reviewEntries.removeAll { $0.id == word.entryID }
        loadFavorites()
    }

    func entry(for word: LegacyLearningWord) -> DictionaryEntry {
        DictionaryEntry(id: word.entryID, russian: word.russian, chinese: word.chinese,
                        category: word.category, source: "我的单词（含旧版迁移）", license: "个人内容",
                        reviewStatus: "personal", tier: 3)
    }

    func exportProgress() throws -> Data {
        guard let learning else { throw LearningStorageError.invalidData("记录尚未打开") }
        return try learning.exportData()
    }

    func restoreProgress(_ data: Data) {
        guard let learning else { errorMessage = "学习记录尚未成功打开。"; return }
        do {
            // Preserve a recoverable copy of the current state before an explicit restore.
            let backup = learning.storageURL.deletingLastPathComponent()
                .appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try learning.exportData().write(to: backup, options: .atomic)
            try learning.restore(from: data)
            reviewTask?.cancel()
            reviewEntries = []
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func modify(_ operation: (LearningStateRepository) throws -> Void) {
        guard let learning else { errorMessage = "学习记录尚未成功打开。"; return }
        do { try operation(learning); refreshProgress() }
        catch { errorMessage = error.localizedDescription }
    }

    private func refreshProgress() {
        guard let learning else { return }
        dailyGoal = learning.state.dailyGoal
        todayCount = learning.todayNewCount()
        streak = learning.streak()
        dueCount = learning.dueEntryIDs().count
        personalWords = learning.state.legacyWords
        legacyCount = personalWords.count
        revision += 1
    }

    private func loadFavorites() {
        favoritesTask?.cancel()
        let ids = (learning?.state.favorites ?? []).sorted()
        favoritesTask = Task {
            do {
                let entries = try await resolve(ids: ids)
                try Task.checkCancellation()
                favorites = entries
                if selectedScope == .favorites { search() }
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func resolve(ids: [String]) async throws -> [DictionaryEntry] {
        let external = ids.filter { !$0.hasPrefix("legacy:") }
        let found = try await dictionary?.entries(ids: external) ?? []
        var lookup = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        for word in personalWords { lookup[word.entryID] = entry(for: word) }
        return ids.compactMap { lookup[$0] }
    }
}
