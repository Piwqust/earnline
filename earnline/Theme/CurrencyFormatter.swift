import Foundation

/// Formats money the earn›line way: a leading/trailing symbol with
/// space-grouped thousands ("$3 222", "250 513 ₽") — matching the Figma.
enum CurrencyFormatter {
    static let symbols: [String: String] = [
        "USD": "$", "RUB": "₽", "EUR": "€", "GBP": "£", "UAH": "₴",
    ]

    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}" // no-break space (consistent, visible)
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    static func grouped(_ value: Decimal) -> String {
        grouping.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Symbol-prefixed (e.g. "$3 222"). Currencies whose symbol trails (₽, ₴) go after.
    static func string(_ value: Decimal, code: String) -> String {
        let symbol = symbols[code] ?? code
        let number = grouped(value)
        switch code {
        case "RUB", "UAH":
            return "\(number) \(symbol)"
        default:
            return "\(symbol)\(number)"
        }
    }

    static func symbol(for code: String) -> String { symbols[code] ?? code }
}
