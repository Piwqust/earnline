import Foundation
import Testing
@testable import earnline

/// Direct coverage for the extracted `CurrencyConverter` value type — the money
/// math that used to be tangled inside `AppModel`.
struct CurrencyConverterTests {
    private func make(rate: Double = 100) -> CurrencyConverter {
        CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: rate)
    }

    @Test func baseCurrencyPassesThroughUnchanged() {
        #expect(make().toBase(240, code: "USD") == 240)
        #expect(make().conversionRate(from: "USD") == 1)
        #expect(make().canConvert("USD"))
    }

    @Test func secondaryCurrencyConvertsByRate() {
        // 5000 RUB at 100 RUB/USD → 50 USD.
        #expect(make(rate: 100).toBase(5000, code: "RUB") == 50)
        #expect(make(rate: 100).canConvert("RUB"))
        #expect(make(rate: 100).conversionRate(from: "RUB") == Decimal(1) / 100)
    }

    @Test func secondaryProjectsBaseAmountUp() {
        // 50 USD at 100 RUB/USD → 5000 RUB.
        #expect(make(rate: 100).secondary(50) == 5000)
    }

    @Test func unknownCurrencyIsExcludedFromConsolidatedTotals() {
        // A third currency has no rate, so it contributes zero to base totals
        // and reports as non-convertible — callers keep showing the original.
        #expect(make().toBase(999, code: "EUR") == 0)
        #expect(make().conversionRate(from: "EUR") == nil)
        #expect(!make().canConvert("EUR"))
    }

    @Test func roundTripBaseToSecondaryAndBackIsStable() {
        let c = make(rate: 83)
        let secondary = c.secondary(120)      // 120 USD → 9960 RUB
        #expect(c.toBase(secondary, code: "RUB") == 120)
    }

    @Test func displayedAmountsRoundHalfUpWithoutFractionDigits() {
        #expect(CurrencyFormatter.string(Decimal(string: "423.49")!, code: "USD") == "$423")
        #expect(CurrencyFormatter.string(Decimal(string: "423.50")!, code: "USD") == "$424")
        #expect(CurrencyFormatter.string(Decimal(string: "423.99")!, code: "RUB") == "424 ₽")
    }
}
