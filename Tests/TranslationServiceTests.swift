import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RussianWordsCore

private final class TranslationProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class TranslationServiceTests: XCTestCase {
    private var session: URLSession!
    private var service: HTTPTranslationService!
    private let endpoint = "https://translation.example.test/translate"
    private let request = TranslationRequest(text: "请帮我找图书馆。", sourceLanguage: .chinese,
                                             targetLanguage: .russian, style: .polite)

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationProtocolStub.self]
        session = URLSession(configuration: configuration)
        service = HTTPTranslationService(session: session)
        TranslationProtocolStub.handler = nil
    }

    override func tearDown() {
        session.invalidateAndCancel()
        TranslationProtocolStub.handler = nil
        service = nil
        session = nil
        super.tearDown()
    }

    func testEndpointRequiresHTTPSAndExcludesEmbeddedCredentials() throws {
        XCTAssertThrowsError(try HTTPTranslationService.validatedEndpoint("  ")) {
            XCTAssertEqual($0 as? TranslationError, .notConfigured)
        }
        for bad in ["http://example.test/translate", "https://", "https://user:password@example.test/translate", "https://example.test/path#fragment"] {
            XCTAssertThrowsError(try HTTPTranslationService.validatedEndpoint(bad)) {
                XCTAssertEqual($0 as? TranslationError, .invalidEndpoint)
            }
        }
        XCTAssertEqual(try HTTPTranslationService.validatedEndpoint("  \(endpoint)\n").absoluteString, endpoint)
    }

    func testChineseRequestCarriesLanguageAndStyleAndDecodesRealResponse() async throws {
        TranslationProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://translation.example.test/translate")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let data = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            XCTAssertEqual(body["text"], "请帮我找图书馆。")
            XCTAssertEqual(body["sourceLanguage"], "zh")
            XCTAssertEqual(body["targetLanguage"], "ru")
            XCTAssertEqual(body["style"], "polite")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"translation\":\"Помогите мне найти библиотеку.\",\"explanation\":\"礼貌请求\"}".utf8))
        }
        let result = try await service.translate(request, endpoint: endpoint)
        XCTAssertEqual(result.translation, "Помогите мне найти библиотеку.")
        XCTAssertEqual(result.explanation, "礼貌请求")
    }

    func testRussianToChineseAndOptionalExplanation() async throws {
        TranslationProtocolStub.handler = { request in
            let body = try JSONDecoder().decode(TranslationRequest.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.sourceLanguage, .russian)
            XCTAssertEqual(body.targetLanguage, .chinese)
            XCTAssertEqual(body.style, .formal)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"translation\":\"我学习俄语。\"}".utf8))
        }
        let query = TranslationRequest(text: "Я изучаю русский язык.", sourceLanguage: .russian,
                                       targetLanguage: .chinese, style: .formal)
        let result = try await service.translate(query, endpoint: endpoint)
        XCTAssertEqual(result.translation, "我学习俄语。")
        XCTAssertNil(result.explanation)
    }

    func testAuthenticationQuotaRateLimitAndServerErrors() async {
        let cases: [(Int, TranslationError)] = [(401, .authenticationRequired), (403, .authenticationRequired),
                                               (402, .quotaExceeded), (429, .rateLimited), (503, .server(503))]
        for (status, expected) in cases {
            stub(status: status, body: "{}")
            await assertServiceError(expected)
        }
    }

    func testMalformedMissingAndBlankTranslationAreRejected() async {
        for body in ["<html>unavailable</html>", "{}", "{\"translation\":\" \"}", "{\"translation\":null}"] {
            stub(status: 200, body: body)
            await assertServiceError(.invalidResponse)
        }
    }

    func testEmptyAndExcessiveInputDoNotReachServer() async {
        TranslationProtocolStub.handler = { _ in
            XCTFail("Invalid input must not be sent to the server")
            throw URLError(.badURL)
        }
        await assertServiceError(.emptyInput, text: " \n ")
        await assertServiceError(.textTooLong, text: String(repeating: "я", count: 5_001))
    }

    func testMissingEndpointDoesNotReachServer() async {
        TranslationProtocolStub.handler = { _ in
            XCTFail("Missing endpoint must not create a request")
            throw URLError(.badURL)
        }
        do {
            _ = try await service.translate(request, endpoint: "")
            XCTFail("Missing endpoint must fail")
        } catch {
            XCTAssertEqual(error as? TranslationError, .notConfigured)
        }
    }

    func testTimeoutAndOfflineErrorsAreDistinguished() async {
        for (code, expected): (URLError.Code, TranslationError) in [(.timedOut, .timeout), (.notConnectedToInternet, .offline), (.networkConnectionLost, .offline)] {
            TranslationProtocolStub.handler = { _ in throw URLError(code) }
            await assertServiceError(expected)
        }
    }

    func testURLSessionCancellationIsNotReportedAsTranslationFailure() async {
        TranslationProtocolStub.handler = { _ in throw URLError(.cancelled) }
        do {
            _ = try await service.translate(request, endpoint: endpoint)
            XCTFail("Cancellation must throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func stub(status: Int, body: String) {
        TranslationProtocolStub.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
    }

    private func assertServiceError(_ expected: TranslationError, text: String? = nil,
                                    file: StaticString = #filePath, line: UInt = #line) async {
        let input = TranslationRequest(text: text ?? request.text, sourceLanguage: request.sourceLanguage,
                                       targetLanguage: request.targetLanguage, style: request.style)
        do {
            _ = try await service.translate(input, endpoint: endpoint)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? TranslationError, expected, file: file, line: line)
        }
    }
}
