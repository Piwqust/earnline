import Foundation
import SwiftData

/// The ledger period represented by a report. A month is a convenience scope;
/// client reports can also use an explicit inclusive date range.
enum ReportScope: Hashable, Sendable {
    case month(containing: Date)
    case dateRange(start: Date, end: Date)

    var isMonth: Bool {
        if case .month = self { return true }
        return false
    }

    func period(calendar: Calendar = .current) -> ReportPeriod {
        switch self {
        case let .month(containing: date):
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return ReportPeriod(start: start, endExclusive: end)

        case let .dateRange(start: rawStart, end: rawEnd):
            let lower = min(rawStart, rawEnd)
            let upper = max(rawStart, rawEnd)
            let start = calendar.startOfDay(for: lower)
            let endDay = calendar.startOfDay(for: upper)
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return ReportPeriod(start: start, endExclusive: end)
        }
    }

    /// The like-for-like period one calendar year before this report. A range
    /// stays a range, and a month stays a month, so January always compares to
    /// January rather than to a raw number of elapsed days.
    func oneYearEarlier(calendar: Calendar = .current) -> ReportScope {
        switch self {
        case let .month(containing: date):
            return .month(containing: calendar.date(byAdding: .year, value: -1, to: date) ?? date)
        case let .dateRange(start: start, end: end):
            return .dateRange(
                start: calendar.date(byAdding: .year, value: -1, to: start) ?? start,
                end: calendar.date(byAdding: .year, value: -1, to: end) ?? end
            )
        }
    }
}

/// The exact closed-open interval used by the snapshot. Keeping the exclusive
/// end avoids accidental inclusion of entries just after a custom range.
struct ReportPeriod: Equatable, Sendable {
    let start: Date
    let endExclusive: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }
}

/// Personal reports may include the whole workspace; client reports deliberately
/// filter every private detail down to one client.
enum ReportAudience: Hashable, Sendable {
    case personal
    case client(id: UUID, name: String)

    var clientID: UUID? {
        guard case let .client(id, _) = self else { return nil }
        return id
    }

    var clientName: String? {
        guard case let .client(_, name) = self else { return nil }
        return name
    }
}

/// A SwiftUI-free status copy safe to carry into a background aggregation task.
enum ReportEntryStatus: String, CaseIterable, Hashable, Sendable {
    case paid
    case inProgress
    case canceled

    init(syncRawValue: String) {
        switch syncRawValue {
        case "logged", "paid": self = .paid
        case "inProgress": self = .inProgress
        case "canceled": self = .canceled
        default: self = .paid
        }
    }

    var isIncludedInEarnings: Bool { self != .canceled }
}

/// One immutable row copied out of SwiftData before report work begins.
struct ReportEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let clientID: UUID
    let clientName: String
    let amount: Decimal
    let currencyCode: String
    let project: String?
    let task: String
    let date: Date
    let holdUntil: Date?
    let status: ReportEntryStatus
}

/// A dated, personal ledger note. Notes never appear in client-facing reports.
struct ReportEventNote: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let date: Date
}

/// A projection of the synced MonthReview model. The Reporting module stays
/// independent from SwiftData schemas, so a caller can map a stored review into
/// this record before building a report.
struct ReportMonthReview: Equatable, Sendable {
    let monthStart: Date
    let note: String
    let closedAt: Date?

    var isClosed: Bool { closedAt != nil }
}

/// Original-currency subtotal. Original units are never added across currencies.
struct ReportCurrencyTotal: Identifiable, Equatable, Sendable {
    let currencyCode: String
    let amount: Decimal
    let entryCount: Int

    var id: String { currencyCode }
}

/// A current-rate USD figure, present only when USD is one of the workspace's
/// configured conversion currencies. Unsupported currencies stay visible in
/// `excludedCurrencyTotals`; they never silently disappear into a fabricated
/// total.
struct ReportUSDEquivalent: Equatable, Sendable {
    let amount: Decimal
    let convertedEntryCount: Int
    let excludedCurrencyTotals: [ReportCurrencyTotal]
    let baseCurrencyCode: String
    let secondaryCurrencyCode: String
    let secondaryUnitsPerBase: Decimal
}

/// Totals for one human status. Canceled records get a count but no financial
/// total, ensuring that canceled work cannot accidentally appear as earned.
struct ReportStatusTotal: Identifiable, Equatable, Sendable {
    let status: ReportEntryStatus
    let entryCount: Int
    let currencyTotals: [ReportCurrencyTotal]
    let usdEquivalent: ReportUSDEquivalent?

    var id: ReportEntryStatus { status }
}

/// Per-currency year-over-year comparison. This is intentionally never a raw
/// cross-currency delta: USD and EUR remain separate rows.
struct ReportCurrencyChange: Identifiable, Equatable, Sendable {
    let currencyCode: String
    let current: Decimal
    let previous: Decimal

    var id: String { currencyCode }
    var difference: Decimal { current - previous }
}

struct ReportUSDChange: Equatable, Sendable {
    let current: Decimal
    let previous: Decimal

    var difference: Decimal { current - previous }
}

/// Personal-only comparison for the equivalent prior calendar period.
struct ReportLastYearComparison: Equatable, Sendable {
    let period: ReportPeriod
    let entryCount: Int
    let currencyChanges: [ReportCurrencyChange]
    let usdEquivalent: ReportUSDChange?
}

/// The complete, actor-independent representation rendered into report cards.
/// It contains values only — never live SwiftData models — so creating PNGs
/// cannot refault the ledger or make a shared sheet show changing figures.
struct ReportSnapshot: Equatable, Sendable {
    let scope: ReportScope
    let audience: ReportAudience
    let period: ReportPeriod
    let generatedAt: Date
    let entries: [ReportEntry]
    let eventNotes: [ReportEventNote]
    let clientCount: Int
    let includedEntryCount: Int
    let canceledEntryCount: Int
    let originalCurrencyTotals: [ReportCurrencyTotal]
    let paid: ReportStatusTotal
    let inProgress: ReportStatusTotal
    let usdEquivalent: ReportUSDEquivalent?
    let lastYearComparison: ReportLastYearComparison?
    let monthReview: ReportMonthReview?

    var totalEntryCount: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty && eventNotes.isEmpty }
}

/// The SwiftData-free source passed to `ReportSnapshotBuilder`. It can be
/// created on the main actor from live models, then safely sent to another actor
/// for aggregation and rendering preparation.
struct ReportSnapshotInput: Sendable {
    let entries: [ReportEntry]
    let eventNotes: [ReportEventNote]
    let monthReviews: [ReportMonthReview]
    let converter: CurrencyConverter

    init(
        entries: [ReportEntry],
        eventNotes: [ReportEventNote] = [],
        monthReviews: [ReportMonthReview] = [],
        converter: CurrencyConverter
    ) {
        self.entries = entries
        self.eventNotes = eventNotes
        self.monthReviews = monthReviews
        self.converter = converter
    }

    /// Copies the minimum report data from SwiftData exactly once. `Heading`
    /// stays the persisted compatibility model while reports call it a note.
    @MainActor
    init(
        clients: [Client],
        headings: [Heading],
        monthReviews: [ReportMonthReview] = [],
        converter: CurrencyConverter
    ) {
        entries = clients.flatMap { client -> [ReportEntry] in
            guard !client.isDeleted else { return [] }
            return client.entries.compactMap { entry in
                guard !entry.isDeleted else { return nil }
                return ReportEntry(
                    id: entry.id,
                    clientID: client.id,
                    clientName: client.name,
                    amount: entry.amount,
                    currencyCode: entry.currencyCode,
                    project: entry.project,
                    task: entry.task,
                    date: entry.date,
                    holdUntil: entry.holdUntil,
                    status: ReportEntryStatus(syncRawValue: entry.statusRaw)
                )
            }
        }
        eventNotes = headings.compactMap { heading in
            guard !heading.isDeleted else { return nil }
            let text = heading.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return ReportEventNote(id: heading.id, text: text, date: heading.date)
        }
        self.monthReviews = monthReviews
        self.converter = converter
    }

    /// Convenience bridge for the synced SwiftData model. The resulting input
    /// remains plain `Sendable` values; report aggregation never retains the
    /// live `MonthReview` instances.
    @MainActor
    init(
        clients: [Client],
        headings: [Heading],
        reviews: [MonthReview],
        converter: CurrencyConverter
    ) {
        self.init(
            clients: clients,
            headings: headings,
            monthReviews: reviews.compactMap { review in
                guard !review.isDeleted else { return nil }
                return ReportMonthReview(
                    monthStart: review.monthStart,
                    note: review.note,
                    closedAt: review.closedAt
                )
            },
            converter: converter
        )
    }
}
