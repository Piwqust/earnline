import SwiftUI

/// A stable row identifier which also retains the represented month for tests
/// and other value-only ledger projections.
struct LedgerScrollTarget: Hashable {
    let rawValue: String
    let representedMonth: Date
}

/// The six-month summary needs data through five calendar months before its
/// displayed month. Keep this boundary check value-only so it is predictable
/// over January and independently testable from the scrolling view.
enum LedgerWindowPrefetch {
    static func needsExtension(
        for displayedMonth: Date,
        windowStart: Date,
        hasOlderMonths: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard hasOlderMonths,
              let trendStart = calendar.date(byAdding: .month, value: -5, to: displayedMonth)
        else { return false }
        return trendStart < windowStart
    }
}

enum LedgerRow: Identifiable {
    typealias ID = LedgerScrollTarget

    /// Month and client rows carry their earned total, computed once in the
    /// snapshot pass — a row must never re-derive it by walking entries.
    case month(Date, Decimal)
    case heading(Heading, Date)
    case client(Client, Date, Decimal)
    case composer(Client, Date)
    case entry(Entry, Date)

    var id: LedgerScrollTarget {
        switch self {
        case .month(let date, _):
            LedgerScrollTarget(rawValue: "m-\(date.timeIntervalSinceReferenceDate)", representedMonth: date)
        case .heading(let heading, let month):
            LedgerScrollTarget(rawValue: "h-\(heading.id)", representedMonth: month)
        case .client(let client, let month, _):
            LedgerScrollTarget(rawValue: "c-\(client.id)-\(month.timeIntervalSinceReferenceDate)", representedMonth: month)
        case .composer(let client, let month):
            LedgerScrollTarget(rawValue: "composer-\(client.id)-\(month.timeIntervalSinceReferenceDate)", representedMonth: month)
        case .entry(let entry, let month):
            LedgerScrollTarget(rawValue: "e-\(entry.id)", representedMonth: month)
        }
    }

    var representedMonth: Date { id.representedMonth }

    var isMonthMarker: Bool {
        if case .month = self { return true }
        return false
    }

    /// A sync pull can invalidate a model while a recycled List row still
    /// exists. Registration metadata remains safe to inspect in that window.
    var isInvalidated: Bool {
        switch self {
        case .month: false
        case .heading(let heading, _): heading.isInvalidated
        case .client(let client, _, _): client.isInvalidated
        case .composer(let client, _): client.isInvalidated
        case .entry(let entry, _): entry.isInvalidated
        }
    }
}

enum LedgerBlock: Identifiable {
    case heading(Heading)
    case client(Client)

    var id: String {
        switch self {
        case .heading(let heading): "h-\(heading.id)"
        case .client(let client): "c-\(client.id)"
        }
    }

    var sortIndex: Int {
        switch self {
        case .heading(let heading): heading.sortIndex
        case .client(let client): client.sortIndex
        }
    }

}
