import Foundation

/// Formats money the earn›line way: a leading/trailing symbol with
/// space-grouped thousands ("$3 222", "250 513 ₽") — matching the Figma.
enum CurrencyFormatter {
    static let symbols: [String: String] = [
        "USD": "$", "RUB": "₽", "EUR": "€", "GBP": "£", "UAH": "₴",
    ]

    private static func formatter(for code: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}" // no-break space (consistent, visible)
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = fractionDigits(for: code)
        f.minimumFractionDigits = 0
        return f
    }

    static func fractionDigits(for code: String) -> Int {
        switch code {
        case "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF":
            return 0
        default:
            return 2
        }
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
}
