import Foundation

/// Foundation-only storage. Call on one serialized executor (the UI uses the main actor).
/// Content databases and learning progress have different lifetimes and storage paths.
public final class LearningStateRepository {
    public static let legacyKey = "perfect_russian_words_v10"
    public private(set) var state: LearningProgress
    public let storageURL: URL
    private let calendar: Calendar

    public init(storageURL: URL, legacyDefaults: UserDefaults? = .standard, calendar: Calendar = .current, now: Date = Date()) throws {
        self.storageURL = storageURL
        self.calendar = calendar
        if FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                state = try Self.decode(Data(contentsOf: storageURL))
            } catch let error as LearningStorageError {
                throw error
            } catch {
                throw LearningStorageError.invalidData(error.localizedDescription)
            }
        } else {
            var initial = LearningProgress()
            if let legacyData = legacyDefaults?.data(forKey: Self.legacyKey) {
                do {
                    initial.legacyWords = try JSONDecoder().decode([LegacyLearningWord].self, from: legacyData)
                } catch {
                    throw LearningStorageError.invalidData("旧版词库迁移失败：\(error.localizedDescription)")
                }
                for word in initial.legacyWords where word.isMastered {
                    // Preserve prior mastery without inventing reviews or a study streak.
                    var record = ReviewRecord(entryID: word.entryID, dueDate: now)
                    record.repetitions = 3
                    record.intervalDays = 21
                    initial.records[word.entryID] = record
                }
            }
            initial.legacyMigrationCompleted = true
            state = initial
            try Self.validate(initial)
            try persist(initial)
        }
    }

    public func review(entryID: String, rating: ReviewRating, now: Date = Date()) throws {
        guard !entryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LearningStorageError.emptyEntryID }
        var next = state
        let previous = next.records[entryID]
        let record = (previous ?? ReviewRecord(entryID: entryID, dueDate: now)).applying(rating, at: now, calendar: calendar)
        next.records[entryID] = record
        let key = dayKey(now)
        var day = next.days[key] ?? StudyDay()
        day.totalAnswers += 1
        if rating.quality >= 3 { day.correctAnswers += 1 }
        day.reviewedEntryIDs.insert(entryID)
        // Explicitly enrolled entries have reviewCount 0; migrated mastery is not a new word.
        let isMigratedMastered = next.legacyWords.contains { $0.entryID == entryID && $0.isMastered }
        if (previous == nil || previous?.reviewCount == 0) && !isMigratedMastered { day.newEntryIDs.insert(entryID) }
        next.days[key] = day
        try update(next)
    }

    /// Only an explicit user action should enroll a reference-only entry.
    public func enroll(entryID: String, now: Date = Date()) throws {
        guard !entryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LearningStorageError.emptyEntryID }
        guard state.records[entryID] == nil else { return }
        var next = state
        next.records[entryID] = ReviewRecord(entryID: entryID, dueDate: now)
        try update(next)
    }

    /// Personal content is kept in its own collection and never counts as reviewed dictionary content.
    @discardableResult
    public func addPersonalWord(russian: String, chinese: String, phonetic: String = "", category: String = "我的单词") throws -> String {
        let russian = russian.trimmingCharacters(in: .whitespacesAndNewlines)
        let chinese = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !russian.isEmpty, !chinese.isEmpty else { throw LearningStorageError.invalidPersonalWord }
        if let existing = state.legacyWords.first(where: {
            $0.russian.compare(russian, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame && $0.chinese == chinese
        }) { return existing.entryID }
        let word = LegacyLearningWord(russian: russian, phonetic: phonetic.trimmingCharacters(in: .whitespacesAndNewlines), chinese: chinese, category: category)
        var next = state
        next.legacyWords.append(word)
        try update(next)
        return word.entryID
    }

    public func updatePersonalWord(entryID: String, russian: String, chinese: String, phonetic: String, category: String) throws {
        let russian = russian.trimmingCharacters(in: .whitespacesAndNewlines)
        let chinese = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !russian.isEmpty, !chinese.isEmpty else { throw LearningStorageError.invalidPersonalWord }
        guard let index = state.legacyWords.firstIndex(where: { $0.entryID == entryID }) else {
            throw LearningStorageError.personalWordNotFound
        }
        var next = state
        next.legacyWords[index].russian = russian
        next.legacyWords[index].chinese = chinese
        next.legacyWords[index].phonetic = phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        next.legacyWords[index].category = category
        try update(next)
    }

    public func deletePersonalWord(entryID: String) throws {
        guard state.legacyWords.contains(where: { $0.entryID == entryID }) else { throw LearningStorageError.personalWordNotFound }
        var next = state
        next.legacyWords.removeAll { $0.entryID == entryID }
        next.records.removeValue(forKey: entryID)
        next.favorites.remove(entryID)
        // Keep historical counts intact; deleting content must not rewrite study history.
        try update(next)
    }

    public func setFavorite(entryID: String, isFavorite: Bool) throws {
        guard !entryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LearningStorageError.emptyEntryID }
        var next = state
        if isFavorite { next.favorites.insert(entryID) } else { next.favorites.remove(entryID) }
        try update(next)
    }

    public func setDailyGoal(_ goal: Int) throws {
        guard (1...100).contains(goal) else { throw LearningStorageError.invalidGoal }
        var next = state
        next.dailyGoal = goal
        try update(next)
    }

    public func dueEntryIDs(at now: Date = Date()) -> [String] {
        state.records.values.filter { $0.dueDate <= now }
            .sorted { $0.dueDate == $1.dueDate ? $0.entryID < $1.entryID : $0.dueDate < $1.dueDate }
            .map(\.entryID)
    }

    public func newEntryIDs(from candidates: [LearningCandidate], at now: Date = Date()) -> [String] {
        let learnedToday = state.days[dayKey(now)]?.newEntryIDs.count ?? 0
        let remaining = max(0, state.dailyGoal - learnedToday)
        var seen = Set<String>()
        let eligible = candidates.filter {
            $0.isEligibleForAutomaticStudy && state.records[$0.id] == nil && seen.insert($0.id).inserted
        }
        return Array(eligible.sorted {
            if $0.tier != $1.tier { return $0.tier.rawValue < $1.tier.rawValue }
            let left = $0.frequencyRank ?? Int.max
            let right = $1.frequencyRank ?? Int.max
            return left == right ? $0.id < $1.id : left < right
        }.prefix(remaining).map(\.id))
    }

    public func todayReviewCount(at now: Date = Date()) -> Int {
        state.days[dayKey(now)]?.totalAnswers ?? 0
    }

    public func todayNewCount(at now: Date = Date()) -> Int {
        state.days[dayKey(now)]?.newEntryIDs.count ?? 0
    }

    public func todayAccuracy(at now: Date = Date()) -> Double? {
        state.days[dayKey(now)]?.accuracy
    }

    public func streak(at now: Date = Date()) -> Int {
        var day = calendar.startOfDay(for: now)
        if (state.days[dayKey(day)]?.totalAnswers ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (state.days[dayKey(day)]?.totalAnswers ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Versioned JSON backup; restore validates first and performs an atomic replacement.
    public func exportData() throws -> Data {
        try Self.encoder().encode(state)
    }

    public func restore(from data: Data) throws {
        try update(Self.decode(data))
    }

    public func dayKey(_ date: Date) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    private func update(_ next: LearningProgress) throws {
        try Self.validate(next)
        try persist(next)
        state = next
    }

    private func persist(_ value: LearningProgress) throws {
        let data = try Self.encoder().encode(value)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decode(_ data: Data) throws -> LearningProgress {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value: LearningProgress
        do {
            value = try decoder.decode(LearningProgress.self, from: data)
        } catch {
            throw LearningStorageError.invalidData(error.localizedDescription)
        }
        try validate(value)
        return value
    }

    private static func validate(_ value: LearningProgress) throws {
        guard value.schemaVersion == 1 else { throw LearningStorageError.unsupportedVersion(value.schemaVersion) }
        guard (1...100).contains(value.dailyGoal) else { throw LearningStorageError.invalidGoal }
        guard value.favorites.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LearningStorageError.invalidData("收藏中存在空 ID")
        }
        for (key, record) in value.records {
            guard !key.isEmpty, key == record.entryID, (0...1_000_000).contains(record.repetitions),
                  (0...36_500).contains(record.intervalDays), record.easeFactor.isFinite,
                  record.easeFactor >= 1.3, record.easeFactor <= 100,
                  (0...1_000_000).contains(record.reviewCount), record.lapseCount >= 0, record.lapseCount <= record.reviewCount,
                  record.dueDate.timeIntervalSince1970.isFinite else {
                throw LearningStorageError.invalidData("复习记录字段无效")
            }
        }
        for day in value.days.values {
            guard (0...1_000_000).contains(day.totalAnswers), day.correctAnswers >= 0, day.correctAnswers <= day.totalAnswers,
                  day.newEntryIDs.isSubset(of: day.reviewedEntryIDs),
                  day.reviewedEntryIDs.count <= day.totalAnswers else {
                throw LearningStorageError.invalidData("每日学习统计无效")
            }
        }
        guard Set(value.legacyWords.map(\.id)).count == value.legacyWords.count else {
            throw LearningStorageError.invalidData("旧版词库存在重复 ID")
        }
    }
}
