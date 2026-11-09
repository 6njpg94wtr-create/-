import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

enum DictionaryError: LocalizedError {
    case missing, invalid(String)
    var errorDescription: String? {
        switch self {
        case .missing: return "未找到随应用安装的词典，请检查词典资源是否加入工程。"
        case .invalid(let detail): return "词典读取失败：\(detail)"
        }
    }
}

/// SQLite access is serialized off the main actor. Content is read-only.
actor DictionaryRepository {
    private var database: OpaquePointer?
    private let columns = "id,russian,stressed,chinese,english,part_of_speech,gender,aspect,category,source,license,review_status,frequency_rank,tier"
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if database != nil { sqlite3_close(database) }
            database = nil
            throw DictionaryError.invalid("无法打开数据库")
        }
    }

    deinit { sqlite3_close(database) }

    func stats() throws -> DictionaryStats {
        let rows = try query("""
        SELECT count(*), coalesce(sum(tier=1 AND review_status='verified' AND chinese!=''),0),
        coalesce(sum(tier IN (1,2) AND review_status='verified' AND chinese!=''),0),
        coalesce(sum(chinese!=''),0), coalesce(sum(review_status='verified'),0) FROM entries
        """)
        guard let row = rows.first else { return DictionaryStats() }
        return DictionaryStats(total: Int(row[0]) ?? 0, core: Int(row[1]) ?? 0,
                               basic: Int(row[2]) ?? 0, chinese: Int(row[3]) ?? 0, verified: Int(row[4]) ?? 0)
    }

    func search(_ text: String, scope: LibraryScope, limit: Int = 100) throws -> [DictionaryEntry] {
        let key = RussianSearch.normalize(text)
        var scopeSQL = "1=1"
        if scope == .core { scopeSQL = "tier=1 AND review_status='verified' AND chinese!=''" }
        if scope == .basic { scopeSQL = "tier IN (1,2) AND review_status='verified' AND chinese!=''" }
        if scope == .reference { scopeSQL = "tier=3" }
        let cap = min(max(limit, 1), 500)
        if key.isEmpty {
            return try query("SELECT \(columns) FROM entries WHERE \(scopeSQL) ORDER BY frequency_rank IS NULL,frequency_rank,search_key,id LIMIT \(cap)").map(decode)
        }
        let primary = try query("""
        SELECT \(columns) FROM entries WHERE (\(scopeSQL)) AND
        ((search_key>=? AND search_key<?) OR id IN (SELECT entry_id FROM forms WHERE form_key=?))
        ORDER BY search_key=? DESC, frequency_rank IS NULL,frequency_rank,search_key,id LIMIT \(cap)
        """, [key, key + "\u{10FFFF}", key, key]).map(decode)
        if primary.count >= cap { return primary }
        let escaped = key.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let extra = try query("""
        SELECT \(columns) FROM entries WHERE (\(scopeSQL)) AND
        (search_key LIKE ? ESCAPE '\\' OR lower(english) LIKE ? ESCAPE '\\' OR chinese LIKE ? ESCAPE '\\')
        ORDER BY frequency_rank IS NULL,frequency_rank,search_key,id LIMIT \(cap)
        """, Array(repeating: "%\(escaped)%", count: 3)).map(decode)
        var seen = Set(primary.map(\.id))
        return Array((primary + extra.filter { seen.insert($0.id).inserted }).prefix(cap))
    }

    func entries(ids: [String]) throws -> [DictionaryEntry] {
        var result: [DictionaryEntry] = []
        for start in stride(from: 0, to: ids.count, by: 400) {
            let batch = Array(ids[start..<min(start + 400, ids.count)])
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            result += try query("SELECT \(columns) FROM entries WHERE id IN (\(placeholders))", batch).map(decode)
        }
        let lookup = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }

    func learningCandidates() throws -> [LearningCandidate] {
        try query("SELECT id,tier,frequency_rank FROM entries WHERE tier IN (1,2) AND chinese!='' AND review_status='verified' ORDER BY tier,frequency_rank IS NULL,frequency_rank,id").map {
            LearningCandidate(id: $0[0], tier: LearningTier(rawValue: Int($0[1]) ?? 3) ?? .reference,
                              hasChinese: true, isReviewed: true, frequencyRank: Int($0[2]))
        }
    }

    private func decode(_ row: [String]) -> DictionaryEntry {
        DictionaryEntry(id: row[0], russian: row[1], stressed: row[2], chinese: row[3], english: row[4],
                        partOfSpeech: row[5], gender: row[6], aspect: row[7], category: row[8], source: row[9],
                        license: row[10], reviewStatus: row[11], frequencyRank: Int(row[12]), tier: Int(row[13]) ?? 3)
    }

    private func query(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else { throw failure() }
        }
        var rows: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw failure() }
            rows.append((0..<sqlite3_column_count(statement)).map { index in
                guard let text = sqlite3_column_text(statement, index) else { return "" }
                return String(cString: text)
            })
        }
    }

    private func failure() -> DictionaryError {
        DictionaryError.invalid(String(cString: sqlite3_errmsg(database)))
    }
}
