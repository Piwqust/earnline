import Foundation
import Testing
@testable import earnline

@MainActor
struct CurrencyConversionTests {
    private func makeApp(base: String, secondary: String, rate: Double) -> AppModel {
        let app = AppModel()
        app.baseCurrencyCode = base
        app.secondaryCurrencyCode = secondary
        app.rate = rate
        return app
    }

    @Test func baseCurrencyConvertsOneToOne() {
        let app = makeApp(base: "USD", secondary: "RUB", rate: 100)
        #expect(app.conversionRate(from: "USD") == 1)
        #expect(app.canConvert("USD"))
        #expect(app.toBase(250, code: "USD") == 250)
    }

    @Test func secondaryCurrencyConvertsByRate() {
        let app = makeApp(base: "USD", secondary: "RUB", rate: 100)
        #expect(app.canConvert("RUB"))
        #expect(app.toBase(5000, code: "RUB") == 50)
    }

    @Test func unknownCurrencyIsNotConvertibleAndFallsBackAtPar() {
        let app = makeApp(base: "USD", secondary: "RUB", rate: 100)
        #expect(app.conversionRate(from: "EUR") == nil)
        #expect(app.canConvert("EUR") == false)
        // Lossy 1:1 fallback — surfaced to the user via the UI marker + Settings count.
        #expect(app.toBase(320, code: "EUR") == 320)
    }
}
