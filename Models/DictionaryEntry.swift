import Foundation

enum LibraryScope: String, CaseIterable, Identifiable {
    case all, core, basic, reference, favorites
    var id: String { rawValue }
}

struct DictionaryStats {
    var total = 0
    var core = 0
    var basic = 0
    var chinese = 0
    var verified = 0
}

struct DictionaryEntry: Identifiable, Hashable {
    let id: String
    let russian: String
    let stressed: String
    let chinese: String
    let english: String
    let partOfSpeech: String
    let gender: String
    let aspect: String
    let category: String
    let source: String
    let license: String
    let reviewStatus: String
    let frequencyRank: Int?
    let tier: Int

    var translation: String { chinese.isEmpty ? english : chinese }
    func displayWord(showStress: Bool) -> String {
        showStress && !stressed.isEmpty ? stressed : russian
    }

    init(id: String, russian: String, stressed: String = "", chinese: String = "", english: String = "",
         partOfSpeech: String = "", gender: String = "", aspect: String = "", category: String = "",
         source: String = "", license: String = "", reviewStatus: String = "pending",
         frequencyRank: Int? = nil, tier: Int = 3) {
        self.id = id; self.russian = russian; self.stressed = stressed
        self.chinese = chinese; self.english = english; self.partOfSpeech = partOfSpeech
        self.gender = gender; self.aspect = aspect; self.category = category
        self.source = source; self.license = license; self.reviewStatus = reviewStatus
        self.frequencyRank = frequencyRank; self.tier = tier
    }
}

enum RussianSearch {
    /// Search equivalence never changes the displayed spelling of ё.
    static func normalize(_ text: String) -> String {
        text.lowercased().precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{0301}", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
