import Foundation

/// Pure, view-independent search predicate shared by the search screen.
///
/// Kept free of SwiftUI/SwiftData fetch concerns so it can be unit-tested and
/// reused: the view passes each entry and the resolved client name.
enum EntrySearch {
    /// Case- and diacritic-insensitive match across client name, project, and
    /// task, plus a loose numeric match against the amount ("240" matches $240).
    /// An empty/whitespace query matches everything.
    static func matches(_ entry: Entry, query: String, clientName: String?) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }

        let fields = [clientName, entry.project, entry.task].compactMap { $0 }
        if fields.contains(where: { normalized($0).contains(needle) }) {
            return true
        }
        return amountMatches(entry.amount, query: query)
    }

    /// Case- and diacritic-folded, trimmed form used on both sides of a compare.
    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Loose digit-substring match so "24" finds $240 and "995" finds 99.50.
    private static func amountMatches(_ amount: Decimal, query: String) -> Bool {
        let queryDigits = query.filter(\.isNumber)
        guard !queryDigits.isEmpty else { return false }
        let amountDigits = NSDecimalNumber(decimal: amount).stringValue.filter(\.isNumber)
        return amountDigits.contains(queryDigits)
    }
}
