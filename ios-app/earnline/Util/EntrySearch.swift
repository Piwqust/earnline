import Foundation

/// A structured filter attached to ledger search — the Mail-style tokens that
/// narrow results alongside (and combined with) the typed text.
enum LedgerSearchToken: Identifiable, Hashable {
    case month(Date)
    case year(Int)
    case client(UUID, name: String)
    case project(String)
    case status(EntryStatus)

    var id: String {
        switch self {
        case .month(let month): "month-\(EntrySearch.monthKey(of: month))"
        case .year(let year): "year-\(year)"
        case .client(let id, _): "client-\(id)"
        case .project(let name): "project-\(EntrySearch.normalized(name))"
        case .status(let status): "status-\(status.rawValue)"
        }
    }

    var label: String {
        switch self {
        case .month(let month): DateFormat.monthAndYear(month)
        case .year(let year): String(year)
        case .client(_, let name): name
        case .project(let name): name
        case .status(let status): status.title
        }
    }

    var systemImage: String {
        switch self {
        case .month, .year: "calendar"
        case .client: "person.crop.circle"
        case .project: "folder"
        case .status(let status): status.symbol
        }
    }
}

/// Pure, view-independent search predicate shared by ledger search mode.
///
/// Kept free of SwiftUI/SwiftData fetch concerns so it can be unit-tested and
/// reused: the view passes each entry and the resolved client identity.
enum EntrySearch {
    /// One search pass, compiled once per keystroke/token change and applied
    /// to every entry. Token groups combine the way system filters do: within
    /// a group any token may accept the entry (two clients = either client),
    /// across groups all must accept it (client + month + status all apply).
    /// The typed text then matches on top, exactly as before tokens existed.
    struct Filter {
        private let needle: String
        private let monthKeys: Set<Int>
        private let years: Set<Int>
        private let clientIDs: Set<UUID>
        private let projects: Set<String>
        private let statuses: Set<EntryStatus>
        /// Month-and-year strings ("march 2026") the text match compares
        /// against, memoized per month so a several-thousand-line ledger
        /// formats each month once per pass, not once per entry.
        private let monthText = MonthTextCache()

        init(query: String, tokens: [LedgerSearchToken] = []) {
            needle = EntrySearch.normalized(query)
            var monthKeys: Set<Int> = []
            var years: Set<Int> = []
            var clientIDs: Set<UUID> = []
            var projects: Set<String> = []
            var statuses: Set<EntryStatus> = []
            for token in tokens {
                switch token {
                case .month(let month): monthKeys.insert(EntrySearch.monthKey(of: month))
                case .year(let year): years.insert(year)
                case .client(let id, _): clientIDs.insert(id)
                case .project(let name): projects.insert(EntrySearch.normalized(name))
                case .status(let status): statuses.insert(status)
                }
            }
            self.monthKeys = monthKeys
            self.years = years
            self.clientIDs = clientIDs
            self.projects = projects
            self.statuses = statuses
        }

        /// Whether the filter narrows anything — an idle field matches all.
        var isActive: Bool {
            !needle.isEmpty || !monthKeys.isEmpty || !years.isEmpty
                || !clientIDs.isEmpty || !projects.isEmpty || !statuses.isEmpty
        }

        func matches(_ entry: Entry, clientID: UUID? = nil, clientName: String?) -> Bool {
            if !monthKeys.isEmpty || !years.isEmpty {
                let components = Calendar.current.dateComponents([.year, .month], from: entry.date)
                let key = EntrySearch.monthKey(year: components.year ?? 0, month: components.month ?? 0)
                // Months and years form one date group: either list may claim
                // the entry ("March 2026" or anything in 2025).
                guard monthKeys.contains(key) || years.contains(components.year ?? 0) else {
                    return false
                }
            }
            if !statuses.isEmpty, !statuses.contains(entry.status) { return false }
            if !clientIDs.isEmpty {
                guard let clientID, clientIDs.contains(clientID) else { return false }
            }
            if !projects.isEmpty {
                guard let project = entry.project,
                      projects.contains(EntrySearch.normalized(project)) else { return false }
            }

            guard !needle.isEmpty else { return true }
            let fields = [clientName, entry.project, entry.task].compactMap { $0 }
            if fields.contains(where: { EntrySearch.normalized($0).contains(needle) }) {
                return true
            }
            if EntrySearch.amountMatches(entry.amount, query: needle) { return true }
            // Dates answer text too — "march", "march 2026", "2026" — but only
            // from three characters, so a one-letter query doesn't light up
            // every entry whose month name happens to contain it.
            if needle.count >= 3, monthText.text(for: entry.date).contains(needle) {
                return true
            }
            return false
        }
    }

    /// Case- and diacritic-insensitive match across client name, project, and
    /// task, plus a loose numeric match against the amount ("240" matches $240)
    /// and date text ("march 2026"). An empty/whitespace query matches
    /// everything. Convenience over `Filter` for token-less callers.
    static func matches(_ entry: Entry, query: String, clientName: String?) -> Bool {
        Filter(query: query).matches(entry, clientName: clientName)
    }

    /// Case- and diacritic-folded, trimmed form used on both sides of a compare.
    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func monthKey(of date: Date) -> Int {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return monthKey(year: components.year ?? 0, month: components.month ?? 0)
    }

    private static func monthKey(year: Int, month: Int) -> Int {
        year * 100 + month
    }

    /// Loose digit-substring match so "24" finds $240 and "995" finds 99.50.
    private static func amountMatches(_ amount: Decimal, query: String) -> Bool {
        let queryDigits = query.filter(\.isNumber)
        guard !queryDigits.isEmpty else { return false }
        let amountDigits = NSDecimalNumber(decimal: amount).stringValue.filter(\.isNumber)
        return amountDigits.contains(queryDigits)
    }

    /// Per-pass memo of normalized "month year" strings keyed by month. A
    /// class so the value-typed `Filter` can fill it lazily while matching.
    private final class MonthTextCache {
        private var byKey: [Int: String] = [:]

        func text(for date: Date) -> String {
            let key = EntrySearch.monthKey(of: date)
            if let cached = byKey[key] { return cached }
            let text = EntrySearch.normalized(DateFormat.monthAndYear(date))
            byKey[key] = text
            return text
        }
    }
}

// MARK: - Filter inventory

extension EntrySearch {
    /// Everything the native Filters menu can offer, gathered once when search opens
    /// (one walk over the store) rather than per keystroke.
    struct FilterSource: Equatable {
        /// Months with data, newest first — the full snapshot's contract.
        var months: [Date] = []
        var clients: [ClientRef] = []
        var projects: [String] = []

        struct ClientRef: Equatable {
            let id: UUID
            let name: String
        }

        /// Distinct years with data, newest first.
        var years: [Int] {
            var seen: Set<Int> = []
            return months.compactMap {
                Calendar.current.dateComponents([.year], from: $0).year
            }.filter { seen.insert($0).inserted }
        }

        func months(in year: Int) -> [Date] {
            months.filter { Calendar.current.dateComponents([.year], from: $0).year == year }
        }
    }
}
