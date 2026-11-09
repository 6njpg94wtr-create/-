import Foundation

public enum CourseTaskKind: String, Codable, CaseIterable, Hashable {
    case newVocabulary, review, grammar, examples
}

public enum CourseCompletionState: String, Codable {
    case notStarted, inProgress, completed, notApplicable
}

public struct CourseExampleSentence: Codable, Equatable {
    public let id: String
    public let russian: String
    public let chinese: String
}

/// Editorial content only. Learner completion is stored separately and joined by
/// DailyCourseStatus, so updating a content bundle never overwrites user progress.
public struct DailyCourse: Codable, Equatable {
    public let id: String
    public let revision: Int
    public let dayNumber: Int
    public let title: String
    public let learningGoal: String
    public let vocabularyIDs: [String]
    public let grammarTopic: String
    public let grammarExplanation: String
    public let exampleSentences: [CourseExampleSentence]
    public let reviewIDs: [String]
    public let estimatedMinutes: Int
    public let isSample: Bool

    public var requiredTasks: Set<CourseTaskKind> {
        var tasks = Set<CourseTaskKind>()
        if !vocabularyIDs.isEmpty { tasks.insert(.newVocabulary) }
        if !reviewIDs.isEmpty { tasks.insert(.review) }
        if !grammarTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tasks.insert(.grammar) }
        if !exampleSentences.isEmpty { tasks.insert(.examples) }
        return tasks
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              revision > 0, (1...90).contains(dayNumber), (1...240).contains(estimatedMinutes),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !learningGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !requiredTasks.isEmpty else { throw CourseError.invalid("课程基本字段或天数无效") }
        for ids in [vocabularyIDs, reviewIDs, exampleSentences.map(\.id)] {
            guard Set(ids).count == ids.count, ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw CourseError.invalid("课程内容存在空 ID 或重复 ID")
            }
        }
        guard grammarTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == grammarExplanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              exampleSentences.allSatisfy({ !$0.russian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw CourseError.invalid("语法或例句内容不完整")
        }
    }
}

public struct DailyCourseStatus: Equatable {
    public let course: DailyCourse
    public let completedTasks: Set<CourseTaskKind>

    public func state(for task: CourseTaskKind) -> CourseCompletionState {
        guard course.requiredTasks.contains(task) else { return .notApplicable }
        return completedTasks.contains(task) ? .completed : .notStarted
    }

    public var completionState: CourseCompletionState {
        let completed = completedTasks.intersection(course.requiredTasks)
        if !course.requiredTasks.isEmpty && completed == course.requiredTasks { return .completed }
        return completed.isEmpty ? .notStarted : .inProgress
    }
}

public enum CourseError: LocalizedError {
    case invalid(String), unsupportedVersion(Int), missingResource, unavailableTask
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return "课程数据无效：\(reason)"
        case .unsupportedVersion(let version): return "暂不支持课程数据版本 \(version)，原文件保留。"
        case .missingResource: return "未找到示例课程资源。"
        case .unavailableTask: return "此课程未配置该类任务，不能标记为完成。"
        }
    }
}
