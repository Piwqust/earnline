import Foundation
import Testing
@testable import earnline

struct ExchangeRateTests {
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
}
