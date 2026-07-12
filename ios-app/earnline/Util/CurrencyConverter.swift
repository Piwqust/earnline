import Foundation

/// Pure conversion between the app's base and secondary currencies. Built as a
/// value type from `AppModel`'s current currency settings, so the money math is
/// testable in isolation from UI state and sync — `AppModel` keeps thin
/// forwarders (`toBase`, `primaryString`, …) that delegate here.
struct CurrencyConverter: Sendable {
    let baseCurrencyCode: String
    let secondaryCurrencyCode: String
    /// Secondary units per 1 base unit (e.g. RUB per USD).
    let rate: Double

    private var rateDecimal: Decimal {
        Decimal(string: String(rate), locale: Locale(identifier: "en_US_POSIX"))
            ?? Decimal(AppModel.defaultExchangeRate)
    }

    /// Base-currency value of one unit of `code`, or `nil` when the app has no
    /// rate for it (anything other than the base or secondary currency).
    func conversionRate(from code: String) -> Decimal? {
        if code == baseCurrencyCode { return 1 }
        if code == secondaryCurrencyCode { return 1 / rateDecimal }
        return nil
    }

    /// Whether an amount in `code` can be converted to the base currency.
    func canConvert(_ code: String) -> Bool { conversionRate(from: code) != nil }

    /// Convert an entry amount into the base currency.
    func toBase(_ amount: Decimal, code: String) -> Decimal {
        if code == baseCurrencyCode { return amount }
        if code == secondaryCurrencyCode { return amount / rateDecimal }
        // A third currency is a valid imported or synced state, but adding its
        // raw units to a base-currency total fabricates a financial result.
        // Callers retain and display the entry's original amount; consolidated
        // totals exclude it until a conversion rate is available.
        #if DEBUG
        print("⚠️ toBase: no rate for \(code); excluding it from consolidated totals.")
        #endif
        return .zero
    }

    /// The secondary-currency value for a base amount.
    func secondary(_ base: Decimal) -> Decimal { base * rateDecimal }

    func primaryString(_ base: Decimal) -> String {
        CurrencyFormatter.string(base, code: baseCurrencyCode)
    }
    func secondaryString(_ base: Decimal) -> String {
        CurrencyFormatter.string(secondary(base), code: secondaryCurrencyCode)
    }
}
