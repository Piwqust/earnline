import Foundation

/// Formats money the earn›line way: whole, normally rounded amounts with a
/// leading/trailing symbol and space-grouped thousands ("$3 222", "250 513 ₽").
enum CurrencyFormatter {
    static let symbols: [String: String] = [
        "USD": "$", "RUB": "₽", "EUR": "€", "GBP": "£", "UAH": "₴",
    ]

    private static func formatter(for code: String) -> NumberFormatter {
        let f = NumberFormatter()
        // Amounts stay precise in storage and sync; only the UI presentation is
        // rounded to a whole unit. `.halfUp` makes the boundary explicit and
        // unsurprising: 423.49 → 423, 423.50 → 424.
        f.locale = .autoupdatingCurrent
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}" // no-break space (consistent, visible)
        f.usesGroupingSeparator = true
        f.roundingMode = .halfUp
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }

    static func grouped(_ value: Decimal, code: String) -> String {
        formatter(for: code).string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Symbol-prefixed (e.g. "$3 222"). Currencies whose symbol trails (₽, ₴) go after.
    static func string(_ value: Decimal, code: String) -> String {
        let symbol = symbols[code] ?? code
        let number = grouped(value, code: code)
        switch code {
        case "RUB", "UAH":
            return "\(number) \(symbol)"
        default:
            return "\(symbol)\(number)"
        }
    }

    static func symbol(for code: String) -> String { symbols[code] ?? code }

    /// SF Symbol for a currency, used as the leading glyph in menu rows —
    /// the iOS 26 menu idiom puts an icon on every row's leading edge.
    static func symbolName(for code: String) -> String {
        switch code {
        case "USD": "dollarsign"
        case "EUR": "eurosign"
        case "GBP": "sterlingsign"
        case "RUB": "rublesign"
        case "UAH": "hryvniasign"
        default: "coloncurrencysign"
        }
    }
}
