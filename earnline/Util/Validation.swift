import Foundation

/// Hard limits to keep values sane and layouts inside their borders.
enum Limits {
    static let maxAmount: Decimal = 1_000_000_000
    static let maxAmountDigits = 12
    static let maxProjectLength = 40
    static let maxTaskLength = 140
    static let maxClientNameLength = 24
    static let maxHeadingLength = 40
}

enum Validation {
    /// Clamp an amount into (0, maxAmount].
    static func clampAmount(_ value: Decimal) -> Decimal {
        if value < 0 { return 0 }
        return min(value, Limits.maxAmount)
    }

    /// Keep only digits and a single decimal separator (capped digits) as the user types.
    static func sanitizeAmountInput(_ raw: String) -> String {
        var out = ""
        var seenSeparator = false
        var digitCount = 0
        for ch in raw {
            if ch.isNumber {
                guard digitCount < Limits.maxAmountDigits else { continue }
                out.append(ch); digitCount += 1
            } else if ch == "." || ch == "," {
                guard !seenSeparator else { continue }
                seenSeparator = true
                out.append(".")
            }
        }
        return out
    }

    static func trimmed(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= max ? t : String(t.prefix(max))
    }

    /// Cap a string's length while editing (no trim, so trailing spaces are allowed mid-type).
    static func capped(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max))
    }
}
