import Foundation

/// Like LearningStateRepository, use this store on one serialized executor.
/// Task checkmarks do not grade vocabulary, alter mastery, or advance SM-2.
public final class CourseProgressStore {
    private struct Record: Codable {
        let courseID: String
        let revision: Int
        let dayNumber: Int
        var completedTasks: Set<CourseTaskKind>
        var updatedAt: Date
    }
    private struct Document: Codable {
        var schemaVersion = 1
        var records: [String: Record] = [:]
    }
    public let storageURL: URL
    private var document: Document

    public convenience init(learningStore: LearningStateRepository) throws {
        try self.init(storageURL: learningStore.storageURL.deletingLastPathComponent().appendingPathComponent("course-progress.json"))
    }

    public init(storageURL: URL) throws {
        self.storageURL = storageURL
        if FileManager.default.fileExists(atPath: storageURL.path) {
            document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: storageURL))
            guard document.schemaVersion == 1 else { throw CourseError.unsupportedVersion(document.schemaVersion) }
            for (key, record) in document.records {
                guard key == Self.key(id: record.courseID, revision: record.revision),
                      !record.courseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      record.revision > 0, (1...90).contains(record.dayNumber), record.updatedAt.timeIntervalSince1970.isFinite else {
                    throw CourseError.invalid("课程完成记录无效，原文件保留")
                }
            }
        } else { document = Document() }
    }

    public func status(for course: DailyCourse) throws -> DailyCourseStatus {
        try course.validate()
        let record = document.records[Self.key(id: course.id, revision: course.revision)]
        if let record, record.dayNumber != course.dayNumber { throw CourseError.invalid("课程 ID 与天数不一致") }
        return DailyCourseStatus(course: course, completedTasks: (record?.completedTasks ?? []).intersection(course.requiredTasks))
    }

    public func setTask(_ task: CourseTaskKind, completed: Bool, for course: DailyCourse, now: Date = Date()) throws {
        let current = try status(for: course)
        guard course.requiredTasks.contains(task) else { throw CourseError.unavailableTask }
        var tasks = current.completedTasks
        if completed { tasks.insert(task) } else { tasks.remove(task) }
        var next = document
        next.records[Self.key(id: course.id, revision: course.revision)] = Record(
            courseID: course.id, revision: course.revision, dayNumber: course.dayNumber, completedTasks: tasks, updatedAt: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(next)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
        document = next
    }

    private static func key(id: String, revision: Int) -> String { "\(id)@\(revision)" }
}
