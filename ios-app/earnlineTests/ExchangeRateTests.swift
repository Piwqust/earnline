import Foundation
import Testing
@testable import earnline

@Suite(.serialized)
struct ExchangeRateTests {
    private final class RateTransport: URLProtocol {
        nonisolated(unsafe) static var statusCode = 200
        nonisolated(unsafe) static var payload = Data()

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.payload)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func session(statusCode: Int, payload: Data) -> URLSession {
        RateTransport.statusCode = statusCode
        RateTransport.payload = payload
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RateTransport.self]
        return URLSession(configuration: configuration)
    }

    private let fixture = Data("""
    {"result":"success","base_code":"USD","rates":{"USD":1,"RUB":83.42658,"UAH":41.9}}
    """.utf8)

    @Test func decodesAndRoundsRate() throws {
        #expect(try ExchangeRateService.rate(from: fixture, secondary: "RUB") == 83.4266)
        #expect(try ExchangeRateService.rate(from: fixture, secondary: "UAH") == 41.9)
    }

    @Test func missingCurrencyThrowsUnsupportedPair() {
        #expect(throws: ExchangeRateService.FetchError.unsupportedPair("EUR")) {
            try ExchangeRateService.rate(from: fixture, secondary: "EUR")
        }
    }

    @Test func errorPayloadThrowsMalformed() {
        let error = Data(#"{"result":"error","error-type":"invalid-key"}"#.utf8)
        #expect(throws: ExchangeRateService.FetchError.malformedResponse) {
            try ExchangeRateService.rate(from: error, secondary: "RUB")
        }
        #expect(throws: ExchangeRateService.FetchError.malformedResponse) {
            try ExchangeRateService.rate(from: Data("not json".utf8), secondary: "RUB")
        }
    }

    @Test func fetchChecksHTTPStatusBeforeDecoding() async {
        await #expect(throws: ExchangeRateService.FetchError.httpStatus(503)) {
            try await ExchangeRateService.fetch(
                base: "USD",
                secondary: "RUB",
                session: session(statusCode: 503, payload: Data("{}".utf8))
            )
        }
    }

    @Test func fetchUsesInjectedSessionAndReturnsTheRequestedPair() async throws {
        let rate = try await ExchangeRateService.fetch(
            base: "USD",
            secondary: "RUB",
            session: session(statusCode: 200, payload: fixture)
        )
        #expect(rate == 83.4266)
    }
}
