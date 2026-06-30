import Foundation

/// Understands a freeform income line and extracts its facets.
///
/// Examples it handles:
///   "+$240 Acme: 2 screens hold until 25.07.26"
///   "✅ $300 Studio X: Landing page"
///   "⌛ 140 ₽ Acme: Logotype hold 14.03"
enum LineParser {
    static let currencyBySymbol: [Character: String] = [
        "$": "USD", "₽": "RUB", "€": "EUR", "£": "GBP", "₴": "UAH",
    ]

    private static let paidMarks: Set<Character> = ["✅", "✔", "✓", "☑"]
    private static let progressMarks: Set<Character> = ["⌛", "⏳", "🕓", "🟠", "🟡", "◐"]
    private static let cancelMarks: Set<Character> = ["❌", "✖", "✗", "🚫", "🔴"]

    /// Parse a pasted multi-line block into one `ParsedLine` per non-empty line.
    /// Shared by the paste-import sheet; callers filter on `ParsedLine.isCommittable`.
    static func parseBlock(_ raw: String, defaultCurrency: String = "USD", referenceDate: Date = .now) -> [ParsedLine] {
        raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { parse($0, defaultCurrency: defaultCurrency, referenceDate: referenceDate) }
    }

    static func parse(_ raw: String, defaultCurrency: String = "USD", referenceDate: Date = .now) -> ParsedLine {
        var result = ParsedLine(currencyCode: defaultCurrency)
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Leading status marker (emoji)
        if let status = leadingStatus(&working) {
            result.status = status
        }

        // 2) "hold until <date>" phrase (remove so its digits don't confuse the amount)
        if let (date, range) = extractHoldDate(in: working, referenceDate: referenceDate) {
            result.holdUntil = date
            working.removeSubrange(range)
            working = working.trimmingCharacters(in: .whitespaces)
        }

        // 3) Amount + currency
        if let amount = extractAmount(&working) {
            result.amount = amount.value
            result.currencyCode = amount.code ?? defaultCurrency
        }

        // 4) "Project : Task"
        working = working.trimmingCharacters(in: CharacterSet(charactersIn: " +\t·"))
        if let colon = working.firstIndex(of: ":") {
            let left = String(working[..<colon]).trimmingCharacters(in: .whitespaces)
            let right = String(working[working.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            result.project = left.isEmpty ? nil : left
            result.task = right
        } else {
            result.task = working
        }
        return result
    }

    // MARK: - Status

    private static func leadingStatus(_ s: inout String) -> EntryStatus? {
        var status: EntryStatus?
        var consumed = true
        while consumed, let first = s.first {
            consumed = false
            if paidMarks.contains(first) {
                status = .paid; consumed = true
            } else if progressMarks.contains(first) {
                status = .inProgress; consumed = true
            } else if cancelMarks.contains(first) {
                status = .canceled; consumed = true
            } else if first == "+" || first.isWhitespace || first == "\u{FE0F}" {
                consumed = true // strip decoration / variation selector
            }
            if consumed { s.removeFirst() }
        }
        s = s.trimmingCharacters(in: .whitespaces)
        return status
    }

    // MARK: - Amount

    struct AmountMatch { var value: Decimal; var code: String? }

    private static func extractAmount(_ s: inout String) -> AmountMatch? {
        let symbolClass = "$€₽£₴"
        let numberClass = "0-9.,\u{2009}\u{00A0} "
        // symbol-first OR number-first
        let patterns = [
            "([\(symbolClass)])\\s?([0-9][\(numberClass)]*[0-9]|[0-9])\\s?([kKкК])?",
            "([0-9][\(numberClass)]*[0-9]|[0-9])\\s?([kKкК])?\\s?([\(symbolClass)])",
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let full = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: full),
                  let whole = Range(m.range, in: s) else { continue }
            let symbolGroup = index == 0 ? 1 : 3
            let numberGroup = index == 0 ? 2 : 1
            let multiplierGroup = index == 0 ? 3 : 2
            guard let symRange = Range(m.range(at: symbolGroup), in: s),
                  let numRange = Range(m.range(at: numberGroup), in: s) else { continue }
            let symbol = s[symRange].first
            let code = symbol.flatMap { currencyBySymbol[$0] }
            if var value = decimal(from: String(s[numRange])) {
                if Range(m.range(at: multiplierGroup), in: s) != nil {
                    value *= 1000
                }
                s.removeSubrange(whole)
                s = s.trimmingCharacters(in: .whitespaces)
                return AmountMatch(value: value, code: code)
            }
        }

        // Fallback: a leading bare number (2+ digits), e.g. "240 Acme: ..."
        if let regex = try? NSRegularExpression(pattern: "^([0-9][0-9.,\u{2009}\u{00A0} ]*[0-9])(?=\\s)"),
           let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let whole = Range(m.range, in: s),
           let value = decimal(from: String(s[whole])) {
            s.removeSubrange(whole)
            s = s.trimmingCharacters(in: .whitespaces)
            return AmountMatch(value: value, code: nil)
        }
        return nil
    }

    /// Normalize a grouped numeric string ("1 000", "1,250.50") into a Decimal.
    static func decimal(from raw: String) -> Decimal? {
        var s = raw.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{2009}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        let hasComma = s.contains(","), hasDot = s.contains(".")
        if hasComma && hasDot {
            s = s.replacingOccurrences(of: ",", with: "") // comma = thousands
        } else if hasComma {
            // decimal only if a single comma with 1–2 trailing digits
            let parts = s.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count <= 2 {
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasDot {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            if !(parts.count == 2 && parts[1].count <= 2) {
                s = s.replacingOccurrences(of: ".", with: "")
            }
        }
        return Decimal(string: s)
    }

    // MARK: - Hold date

    private static let holdRegex = try? NSRegularExpression(
        pattern: "(?i)(?:hold\\s*(?:until|till|til)?|until|till|due)\\s*:?\\s*(\\d{1,2})[./-](\\d{1,2})(?:[./-](\\d{2,4}))?"
    )

    private static func extractHoldDate(in s: String, referenceDate: Date) -> (Date, Range<String.Index>)? {
        guard let regex = holdRegex else { return nil }
        let full = NSRange(s.startIndex..., in: s)
        guard let m = regex.firstMatch(in: s, range: full),
              let whole = Range(m.range, in: s),
              let dRange = Range(m.range(at: 1), in: s),
              let mRange = Range(m.range(at: 2), in: s),
              let day = Int(s[dRange]),
              let month = Int(s[mRange]) else { return nil }

        let calendar = Calendar.current
        var year = calendar.component(.year, from: referenceDate)
        var hasExplicitYear = false
        if let yRange = Range(m.range(at: 3), in: s), let y = Int(s[yRange]) {
            year = y < 100 ? 2000 + y : y
            hasExplicitYear = true
        }
        var comps = DateComponents()
        comps.day = day; comps.month = month; comps.year = year
        guard var date = calendar.date(from: comps) else { return nil }
        if !hasExplicitYear, date < calendar.startOfDay(for: referenceDate) {
            comps.year = year + 1
            guard let rolloverDate = calendar.date(from: comps) else { return nil }
            date = rolloverDate
        }
        return (date, whole)
    }
}
