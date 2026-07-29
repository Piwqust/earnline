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

    /// Like `parseBlock`, but understands Notes-style month headings between
    /// lines ("— Income for April", "Доходы за май 2025"): income lines under a
    /// heading are dated to that month instead of today.
    static func parseLedgerBlock(_ raw: String,
                                 defaultCurrency: String = "USD",
                                 referenceDate: Date = .now) -> [ParsedLine] {
        var currentMonth: Date?
        var result: [ParsedLine] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let month = sectionMonth(line, referenceDate: referenceDate) {
                currentMonth = month
                continue
            }
            var parsed = parse(line, defaultCurrency: defaultCurrency, referenceDate: referenceDate)
            parsed.date = currentMonth
            result.append(parsed)
        }
        return result
    }

    /// A month-section heading, or nil when the line is a normal income line.
    /// Returns the first day of the named month. A heading is a line that looks
    /// like one (leading dash or an "income for" phrase) and names a month.
    static func sectionMonth(_ line: String,
                             referenceDate: Date = .now,
                             calendar: Calendar = .current) -> Date? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let looksLikeHeading = trimmed.hasPrefix("—") || trimmed.hasPrefix("–") || trimmed.hasPrefix("-")
            || trimmed.localizedCaseInsensitiveContains("Income for")
            || trimmed.localizedCaseInsensitiveContains("Доходы за")
            || trimmed.localizedCaseInsensitiveContains("Дохід за")
        guard looksLikeHeading,
              let month = monthStems.first(where: { containsMonthStem(trimmed, $0.stem) })?.month else {
            return nil
        }
        let year: Int
        if let match = trimmed.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression),
           let explicit = Int(trimmed[match]) {
            year = explicit
        } else {
            // Pasted ledgers are history — a month "after" the current one
            // means the previous year, not the future.
            let currentYear = calendar.component(.year, from: referenceDate)
            year = month > calendar.component(.month, from: referenceDate) ? currentYear - 1 : currentYear
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    /// Month-name fragments → month number, EN, RU and UK (shared with the
    /// bundled ledger importer). Stems match both nominative and genitive forms
    /// ("січ" covers "січень" and "за січня").
    static let monthMap: [String: Int] = [
        "январ": 1, "феврал": 2, "март": 3, "апрел": 4, "май": 5, "мая": 5,
        "июн": 6, "июл": 7, "август": 8, "сентябр": 9, "октябр": 10,
        "ноябр": 11, "декабр": 12,
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5,
        "june": 6, "july": 7, "august": 8, "september": 9, "october": 10,
        "november": 11, "december": 12,
        "січ": 1, "лют": 2, "берез": 3, "квіт": 4, "трав": 5, "черв": 6,
        "лип": 7, "серп": 8, "верес": 9, "жовт": 10, "листопад": 11, "груд": 12,
    ]

    /// `monthMap` as a longest-stem-first array so matching is deterministic
    /// (a `Dictionary` iterates in arbitrary order) and the most specific stem
    /// wins.
    private static let monthStems: [(stem: String, month: Int)] = monthMap
        .sorted { $0.key.count != $1.key.count ? $0.key.count > $1.key.count : $0.key < $1.key }
        .map { ($0.key, $0.value) }

    /// Case-insensitive substring search that requires the stem to begin at a
    /// word boundary, so a short stem ("may", "трав") can't match inside a
    /// longer word. Month stems are prefixes of the full month word, so only a
    /// leading boundary is enforced (not a trailing one).
    private static func containsMonthStem(_ haystack: String, _ stem: String) -> Bool {
        guard !stem.isEmpty else { return false }
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let match = haystack.range(of: stem, options: [.caseInsensitive], range: searchRange) {
            let atStart = match.lowerBound == haystack.startIndex
            if atStart || !haystack[haystack.index(before: match.lowerBound)].isLetter {
                return true
            }
            searchRange = match.upperBound..<haystack.endIndex
        }
        return false
    }

    static func parse(_ raw: String, defaultCurrency: String = "USD", referenceDate: Date = .now) -> ParsedLine {
        var result = ParsedLine(currencyCode: defaultCurrency)
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Leading status marker (emoji)
        if let status = leadingStatus(&working) {
            result.status = status
        }

        // 1b) Plain-word status at either end of the line ("Client 500 usd
        // pending", "paid Acme: retainer"). The word is stripped either way;
        // an explicit emoji marker wins if both are present.
        if let status = extractStatusWord(&working) {
            if result.status == nil { result.status = status }
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

    /// Plain-word statuses, EN + RU. Matched case-insensitively but only as a
    /// standalone token at the very start or very end of the line, so task
    /// text like "Paid search ads audit" keeps its words.
    private static let statusWords: [(word: String, status: EntryStatus)] = [
        ("in progress", .inProgress), ("pending", .inProgress), ("waiting", .inProgress),
        ("cancelled", .canceled), ("canceled", .canceled),
        ("paid", .paid), ("done", .paid),
        ("в работе", .inProgress), ("ожидает", .inProgress),
        ("отменено", .canceled), ("отмена", .canceled),
        ("оплачено", .paid), ("готово", .paid),
    ]

    private static func extractStatusWord(_ s: inout String) -> EntryStatus? {
        let lowered = s.lowercased()
        // A *leading* status word is only a marker when the rest of the line
        // still reads as an income line. "Paid search ads audit" is a task, and
        // consuming its first word both lost the word and silently marked the
        // line paid. A trailing word ("Acme retainer paid") is unambiguous —
        // nothing else follows it — so it is always consumed.
        let leadingWordIsAMarker = requiresStructuralContext(s)
        for (word, status) in statusWords {
            if lowered == word {
                s = ""
                return status
            }
            if lowered.hasSuffix(" " + word) {
                s = String(s.dropLast(word.count)).trimmingCharacters(in: .whitespaces)
                return status
            }
            if leadingWordIsAMarker, lowered.hasPrefix(word + " ") {
                s = String(s.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
                return status
            }
        }
        return nil
    }

    /// Whether the line carries the shape of an income line rather than free
    /// prose: a `project: task` colon, a currency symbol, or a number long
    /// enough for `extractAmount`'s bare-number fallback to accept it.
    private static func requiresStructuralContext(_ s: String) -> Bool {
        if s.contains(":") { return true }
        if s.rangeOfCharacter(from: CharacterSet(charactersIn: "$€₽£₴")) != nil { return true }
        if s.range(of: "\\d{2,}", options: .regularExpression) != nil { return true }
        return s.range(of: "(?i)\\d\\s*(k|к|usd|eur|rub|gbp|uah)\\b", options: .regularExpression) != nil
    }

    // MARK: - Amount

    struct AmountMatch { var value: Decimal; var code: String? }

    /// ISO-style text currency codes accepted after a number ("500 usd").
    static let currencyByCode: [String: String] = [
        "usd": "USD", "eur": "EUR", "rub": "RUB", "gbp": "GBP", "uah": "UAH",
    ]

    private static func extractAmount(_ s: inout String) -> AmountMatch? {
        let symbolClass = "$€₽£₴"
        let numberClass = "0-9.,\u{2009}\u{00A0} "
        let number = "[0-9][\(numberClass)]*[0-9]|[0-9]"
        struct AmountPattern {
            let pattern: String
            let numberGroup: Int
            let multiplierGroup: Int
            let symbolGroup: Int?
            let codeGroup: Int?
        }
        let patterns: [AmountPattern] = [
            // symbol-first: "$240", "$ 24k". The thousands suffix must
            // touch the number: otherwise "$260 Карманная…" would consume
            // the first letter of the project as a Cyrillic `к` multiplier.
            .init(pattern: "([\(symbolClass)])\\s?(\(number))([kKкК])?",
                  numberGroup: 2, multiplierGroup: 3, symbolGroup: 1, codeGroup: nil),
            // number-first with trailing symbol: "12 000 ₽", "11k₽"
            .init(pattern: "(\(number))\\s?([kKкК])?\\s?([\(symbolClass)])",
                  numberGroup: 1, multiplierGroup: 2, symbolGroup: 3, codeGroup: nil),
            // number with a text currency code: "500 usd", "24k eur"
            .init(pattern: "(?i)(\(number))\\s?([kKкК])?\\s(usd|eur|rub|gbp|uah)\\b",
                  numberGroup: 1, multiplierGroup: 2, symbolGroup: nil, codeGroup: 3),
        ]
        for candidate in patterns {
            guard let regex = try? NSRegularExpression(pattern: candidate.pattern) else { continue }
            let full = NSRange(s.startIndex..., in: s)
            // Anchored to the line's edges: an amount leads or trails an income
            // line. A number buried mid-prose ("refund the $500 deposit next
            // week") is part of the text, not the line's amount.
            let m = regex.matches(in: s, range: full).first { match in
                guard let whole = Range(match.range, in: s) else { return false }
                return whole.lowerBound == s.startIndex || whole.upperBound == s.endIndex
            }
            guard let m, let whole = Range(m.range, in: s),
                  let numRange = Range(m.range(at: candidate.numberGroup), in: s) else { continue }
            var code: String?
            if let group = candidate.symbolGroup, let symRange = Range(m.range(at: group), in: s) {
                code = s[symRange].first.flatMap { currencyBySymbol[$0] }
            } else if let group = candidate.codeGroup, let codeRange = Range(m.range(at: group), in: s) {
                code = currencyByCode[s[codeRange].lowercased()]
            }
            if var value = decimal(from: String(s[numRange])) {
                if Range(m.range(at: candidate.multiplierGroup), in: s) != nil {
                    value *= 1000
                }
                s.removeSubrange(whole)
                s = s.trimmingCharacters(in: .whitespaces)
                return AmountMatch(value: value, code: code)
            }
        }

        // Fallback: a bare number (2+ digits) leading or trailing the line,
        // e.g. "240 Acme: ..." or "Acme retainer 500". A single bare digit
        // stays text on purpose — "2 screens" is a count, not $2
        // (single-digit amounts still parse with a symbol: "$5").
        let barePatterns = [
            "^([0-9][0-9.,\u{2009}\u{00A0} ]*[0-9])(?=\\s)",
            "(?<=\\s)([0-9][0-9.,\u{2009}\u{00A0} ]*[0-9])$",
        ]
        for pattern in barePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let whole = Range(m.range, in: s),
                  let value = decimal(from: String(s[whole])) else { continue }
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
        if hasComma && hasDot, let lastComma = s.lastIndex(of: ","), let lastDot = s.lastIndex(of: ".") {
            // Both separators present: the last-occurring one is the decimal
            // point (US "1,000.50" and EU "1.000,50"); strip the other as grouping.
            if lastComma > lastDot {
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
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
        pattern: "(?i)\\b(?:hold\\s*(?:until|till|til)?|until|till|due)\\s*:?\\s*(\\d{1,2})[./-](\\d{1,2})(?:[./-](\\d{2,4}))?"
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

        // Reject impossible day/month values instead of letting the lenient
        // calendar roll them into a different real date ("31.02" → March 3,
        // US-style "07/25" → a random month next year).
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        let calendar = Calendar.current
        var year = calendar.component(.year, from: referenceDate)
        var hasExplicitYear = false
        if let yRange = Range(m.range(at: 3), in: s), let y = Int(s[yRange]) {
            year = y < 100 ? 2000 + y : y
            hasExplicitYear = true
        }
        var comps = DateComponents()
        comps.day = day; comps.month = month; comps.year = year
        guard var date = calendar.date(from: comps), isExactDate(date, comps, calendar) else { return nil }
        if !hasExplicitYear, date < calendar.startOfDay(for: referenceDate) {
            comps.year = year + 1
            guard let rolloverDate = calendar.date(from: comps),
                  isExactDate(rolloverDate, comps, calendar) else { return nil }
            date = rolloverDate
        }
        return (date, whole)
    }

    /// True when the calendar didn't normalize the components into a different
    /// day (e.g. Feb 30 → Mar 2).
    private static func isExactDate(_ date: Date, _ comps: DateComponents, _ calendar: Calendar) -> Bool {
        calendar.component(.day, from: date) == comps.day
            && calendar.component(.month, from: date) == comps.month
    }
}
