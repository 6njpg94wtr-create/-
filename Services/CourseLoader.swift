import Foundation

public protocol CourseLoading {
    var availableDays: [Int] { get }
    func course(dayNumber: Int) throws -> DailyCourse?
}

public struct JSONCourseLoader: CourseLoading {
    private struct Catalog: Codable {
        let schemaVersion: Int
        let courses: [DailyCourse]
    }
    private let courses: [DailyCourse]
    public var availableDays: [Int] { courses.map(\.dayNumber).sorted() }

    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.schemaVersion == 1 else { throw CourseError.unsupportedVersion(catalog.schemaVersion) }
        for course in catalog.courses { try course.validate() }
        guard Set(catalog.courses.map(\.dayNumber)).count == catalog.courses.count,
              Set(catalog.courses.map(\.id)).count == catalog.courses.count else {
            throw CourseError.invalid("目录中存在重复课程 ID 或天数")
        }
        courses = catalog.courses
    }

    public init(url: URL) throws { try self.init(data: Data(contentsOf: url)) }

    public static func bundledSample(bundle: Bundle = .main) throws -> JSONCourseLoader {
        guard let url = bundle.url(forResource: "day1.sample", withExtension: "json") else { throw CourseError.missingResource }
        return try JSONCourseLoader(url: url)
    }

    public func course(dayNumber: Int) throws -> DailyCourse? {
        guard (1...90).contains(dayNumber) else { throw CourseError.invalid("课程天数须为 1 至 90") }
        // A missing day is not silently filled with another day's sample.
        return courses.first { $0.dayNumber == dayNumber }
    }
}
