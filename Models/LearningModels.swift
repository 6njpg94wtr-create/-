import Foundation

/// The 1,000 core entries are a subset of the 3,000 basic entries.
/// Reference entries are never silently added to a learner's study plan.
public enum LearningTier: Int, Codable, CaseIterable {
    case core = 1
    case basic = 2
    case reference = 3

    public var targetCount: Int {
        switch self {
        case .core: return 1_000
        case .basic: return 3_000
        case .reference: return 30_000
        }
    }

    public func includes(_ tier: LearningTier) -> Bool {
        switch self {
        case .core: return tier == .core
        case .basic: return tier == .core || tier == .basic
        case .reference: return true
        }
    }
}

public struct LearningCandidate: Identifiable, Equatable {
    public let id: String
    public let tier: LearningTier
    public let hasChinese: Bool
    public let isReviewed: Bool
    public let frequencyRank: Int?

    public init(id: String, tier: LearningTier, hasChinese: Bool, isReviewed: Bool, frequencyRank: Int? = nil) {
        self.id = id
        self.tier = tier
        self.hasChinese = hasChinese
        self.isReviewed = isReviewed
        self.frequencyRank = frequencyRank
    }

    public var isEligibleForAutomaticStudy: Bool {
        !id.isEmpty && tier != .reference && hasChinese && isReviewed
    }
}

/// Four-button adaptation of SM-2, not FSRS.
/// Again=quality 0, Hard=3, Good=4, Easy=5. Failed answers reset repetitions.
public enum ReviewRating: String, Codable, CaseIterable {
    case again, hard, good, easy

    public var quality: Int {
        switch self {
        case .again: return 0
        case .hard: return 3
        case .good: return 4
        case .easy: return 5
        }
    }
}

public struct ReviewRecord: Codable, Equatable {
    public let entryID: String
    public var repetitions: Int
    public var intervalDays: Int
    public var easeFactor: Double
    public var dueDate: Date
    public var lastReviewedAt: Date?
    public var reviewCount: Int
    public var lapseCount: Int

    public init(entryID: String, dueDate: Date) {
        self.entryID = entryID
        repetitions = 0
        intervalDays = 0
        easeFactor = 2.5
        self.dueDate = dueDate
        lastReviewedAt = nil
        reviewCount = 0
        lapseCount = 0
    }

    public func applying(_ rating: ReviewRating, at now: Date, calendar: Calendar = .current) -> ReviewRecord {
        var result = self
        let quality = Double(rating.quality)
        if rating.quality < 3 {
            result.repetitions = 0
            result.intervalDays = 1
            result.lapseCount += 1
        } else {
            switch result.repetitions {
            case 0: result.intervalDays = 1
            case 1: result.intervalDays = 6
            default:
                // A ceiling avoids arithmetic/date overflow for imported long-lived records.
                result.intervalDays = min(36_500, max(1, Int((Double(result.intervalDays) * result.easeFactor).rounded())))
            }
            result.repetitions += 1
        }
        result.easeFactor = min(100, max(1.3, result.easeFactor + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))
        result.dueDate = calendar.date(byAdding: .day, value: result.intervalDays, to: now)
            ?? now.addingTimeInterval(Double(result.intervalDays) * 86_400)
        result.lastReviewedAt = now
        result.reviewCount += 1
        return result
    }
}

public struct StudyDay: Codable, Equatable {
    public var totalAnswers: Int = 0
    public var correctAnswers: Int = 0
    public var reviewedEntryIDs: Set<String> = []
    public var newEntryIDs: Set<String> = []

    public init() {}

    public var accuracy: Double? {
        totalAnswers == 0 ? nil : Double(correctAnswers) / Double(totalAnswers)
    }
}

/// Exact fields of the original version, kept separate from the licensed dictionary.
/// User-added or old example content is never promoted to reviewed teaching data.
public struct LegacyLearningWord: Codable, Identifiable, Equatable {
    public let id: UUID
    public var russian: String
    public var phonetic: String
    public var chinese: String
    public var category: String
    public var isMastered: Bool

    public var entryID: String { "legacy:\(id.uuidString.lowercased())" }

    public init(id: UUID = UUID(), russian: String, phonetic: String, chinese: String, category: String, isMastered: Bool = false) {
        self.id = id
        self.russian = russian
        self.phonetic = phonetic
        self.chinese = chinese
        self.category = category
        self.isMastered = isMastered
    }
}

public struct LearningProgress: Codable, Equatable {
    public var schemaVersion: Int = 1
    public var dailyGoal: Int = 10
    public var records: [String: ReviewRecord] = [:]
    public var favorites: Set<String> = []
    public var days: [String: StudyDay] = [:]
    public var legacyWords: [LegacyLearningWord] = []
    public var legacyMigrationCompleted: Bool = false

    public init() {}
}

public enum LearningStorageError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidData(String)
    case invalidGoal
    case emptyEntryID
    case invalidPersonalWord
    case personalWordNotFound

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "学习记录版本 \(version) 暂不受支持，原文件已保留。"
        case .invalidData(let reason): return "学习记录无法读取，原文件已保留：\(reason)"
        case .invalidGoal: return "每日新词目标须在 1 至 100 之间。"
        case .emptyEntryID: return "缺少词条 ID，无法保存学习记录。"
        case .invalidPersonalWord: return "请填写俄语和中文释义。"
        case .personalWordNotFound: return "该自有词条不存在。"
        }
    }
}
