import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum TranslationLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese = "zh"
    case russian = "ru"

    var id: String { rawValue }
    var title: String { self == .chinese ? "中文" : "俄语" }
    var speechLocale: String { self == .chinese ? "zh-CN" : "ru-RU" }
    var opposite: TranslationLanguage { self == .chinese ? .russian : .chinese }
}

enum TranslationStyle: String, Codable, CaseIterable, Identifiable {
    case natural, formal, polite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .natural: return "自然口语"
        case .formal: return "正式表达"
        case .polite: return "礼貌表达"
        }
    }
}

struct TranslationRequest: Codable, Equatable {
    let text: String
    let sourceLanguage: TranslationLanguage
    let targetLanguage: TranslationLanguage
    let style: TranslationStyle
}

struct TranslationResponse: Codable, Equatable {
    let translation: String
    let explanation: String?
}

enum TranslationError: LocalizedError, Equatable {
    case notConfigured, invalidEndpoint, emptyInput, textTooLong
    case authenticationRequired, quotaExceeded, rateLimited
    case server(Int), invalidResponse, offline, timeout

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先在翻译设置中配置可用的翻译服务。"
        case .invalidEndpoint: return "请输入完整的 HTTPS 翻译接口地址，地址中不能包含账号或密码。"
        case .emptyInput: return "请输入需要翻译的内容。"
        case .textTooLong: return "单次最多翻译 5,000 个字符，请分段翻译。"
        case .authenticationRequired: return "翻译服务需要身份验证。请联系服务提供者配置适用于此 App 的访问方式。"
        case .quotaExceeded: return "翻译服务余额或额度不足，请联系服务提供者。"
        case .rateLimited: return "请求过于频繁或服务额度受限，请稍后重试。"
        case .server(let status): return "翻译服务返回错误（HTTP \(status)），请稍后重试。"
        case .invalidResponse: return "翻译服务返回的内容无法解析，请检查接口格式。"
        case .offline: return "当前无法连接网络。离线词库和学习记录仍可使用。"
        case .timeout: return "翻译请求超时，请检查网络后重试。"
        }
    }
}

protocol TranslationServing {
    func translate(_ request: TranslationRequest, endpoint: String) async throws -> TranslationResponse
}

struct HTTPTranslationService: TranslationServing {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    static func validatedEndpoint(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.notConfigured }
        guard let parts = URLComponents(string: trimmed),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              let url = parts.url else { throw TranslationError.invalidEndpoint }
        return url
    }

    func translate(_ request: TranslationRequest, endpoint: String) async throws -> TranslationResponse {
        let url = try Self.validatedEndpoint(endpoint)
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyInput
        }
        guard request.text.count <= 5_000 else { throw TranslationError.textTooLong }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw TranslationError.authenticationRequired
            case 402: throw TranslationError.quotaExceeded
            case 429: throw TranslationError.rateLimited
            default: throw TranslationError.server(http.statusCode)
            }
            guard let decoded = try? JSONDecoder().decode(TranslationResponse.self, from: data),
                  !decoded.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationError.invalidResponse
            }
            return decoded
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                throw TranslationError.offline
            case .timedOut: throw TranslationError.timeout
            case .cancelled: throw CancellationError()
            default: throw error
            }
        }
    }
}

struct TranslationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let original: String
    let translation: String
    let sourceLanguage: TranslationLanguage
    let style: TranslationStyle
    let explanation: String?
    var isFavorite: Bool
    let isConversation: Bool

    init(request: TranslationRequest, response: TranslationResponse, isConversation: Bool) {
        id = UUID()
        date = Date()
        original = request.text
        translation = response.translation
        sourceLanguage = request.sourceLanguage
        style = request.style
        explanation = response.explanation
        isFavorite = false
        self.isConversation = isConversation
    }
}
