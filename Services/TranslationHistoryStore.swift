import Combine
import Foundation

@MainActor
final class TranslationHistoryStore: ObservableObject {
    static let shared = TranslationHistoryStore()
    @Published private(set) var records: [TranslationRecord] = []
    @Published private(set) var storageError: String?
    private let defaults: UserDefaults
    private let key = "russianwords.translation.history.v1"
    private var canSave = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do {
                records = try JSONDecoder().decode([TranslationRecord].self, from: data)
            } catch {
                canSave = false
                storageError = "翻译历史读取失败，原数据已保留。新的翻译仍可使用，但暂时无法保存历史。"
            }
        }
    }

    func add(_ record: TranslationRecord) {
        let all = [record] + records
        // Preserve favorites; limit only ordinary history to the latest 200 results.
        let recentIDs = Set(all.filter { !$0.isFavorite }.prefix(200).map(\.id))
        save(all.filter { $0.isFavorite || recentIDs.contains($0.id) })
    }

    func toggleFavorite(_ id: UUID) {
        var updated = records
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].isFavorite.toggle()
        save(updated)
    }

    func delete(_ id: UUID) { save(records.filter { $0.id != id }) }

    private func save(_ updated: [TranslationRecord]) {
        guard canSave else { return }
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: key)
            records = updated
            storageError = nil
        } catch {
            storageError = "翻译历史保存失败：\(error.localizedDescription)"
        }
    }
}

@MainActor
final class TranslationController: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var result: TranslationRecord?
    private let service: TranslationServing
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    init(service: TranslationServing = HTTPTranslationService()) { self.service = service }

    func translate(text: String, language: TranslationLanguage, style: TranslationStyle,
                   endpoint: String, isConversation: Bool = false, playbackRate: Float? = nil) {
        cancel()
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        result = nil
        let request = TranslationRequest(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLanguage: language, targetLanguage: language.opposite, style: style
        )
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await self.service.translate(request, endpoint: endpoint)
                guard !Task.isCancelled, self.requestID == id else { return }
                let record = TranslationRecord(request: request, response: response, isConversation: isConversation)
                self.result = record
                TranslationHistoryStore.shared.add(record)
                if let rate = playbackRate {
                    SpeechPlayback.shared.speak(response.translation, language: language.opposite.speechLocale, rate: rate)
                }
            } catch is CancellationError {
                // An intentional interruption should not appear as a translation failure.
            } catch {
                if self.requestID == id { self.errorMessage = error.localizedDescription }
            }
            if self.requestID == id {
                self.isLoading = false
                self.requestID = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestID = nil
        isLoading = false
    }
}
