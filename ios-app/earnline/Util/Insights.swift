import Foundation
import SwiftData

/// Immutable, actor-independent input for the Insights dashboard. SwiftData
/// models are copied once by a private model actor, then all dashboard
/// aggregation can run away from SwiftUI's render path without crossing model
/// isolation.
struct InsightsDashboardInput: Sendable {
    struct ClientRecord: Sendable {
        let id: UUID
        let name: String
        let colorHex: String
        let entries: [EntryRecord]
    }

    struct EntryRecord: Sendable {
        let amount: Decimal
        let currencyCode: String
        let date: Date
        let holdUntil: Date?
        let isEarned: Bool
    }

    let clients: [ClientRecord]
    let converter: CurrencyConverter

    init(records: [ClientRecord], converter: CurrencyConverter) {
        self.clients = records
        self.converter = converter
    }

    @MainActor
    init(clients: [Client], converter: CurrencyConverter) {
        self.converter = converter
        self.clients = clients.compactMap { client in
            guard !client.isDeleted else { return nil }
            return ClientRecord(
                id: client.id,
                name: client.name,
                colorHex: client.colorHex,
                entries: client.entries.compactMap { entry in
                    guard !entry.isDeleted else { return nil }
                    return EntryRecord(
                        amount: entry.amount,
                        currencyCode: entry.currencyCode,
                        date: entry.date,
                        holdUntil: entry.holdUntil,
                        isEarned: entry.status.isIncludedInEarnedTotals
                    )
                }
            )
        }
    }

    /// One pass produces every figure the sheet needs. The leading month before
    /// the visible window is retained only as the first point's comparison base.
    nonisolated func dashboardSnapshot(
        windowMonths: Int = InsightsDashboardSnapshot.chartMonthCount,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> InsightsDashboardSnapshot {
        let count = max(windowMonths, 1)
        let thisMonth = monthStart(now, calendar: calendar)
        let visibleMonths = (0..<count).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: thisMonth)
        }
        let previousMonth = calendar.date(byAdding: .month, value: -count, to: thisMonth)
        let visibleKeys = Set(visibleMonths.map { monthKey($0, calendar: calendar) })
        let comparisonKeys = visibleKeys.union(previousMonth.map { [monthKey($0, calendar: calendar)] } ?? [])
        let windowStart = visibleMonths.first ?? thisMonth
        let windowEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: thisMonth) ?? thisMonth
        let currentYear = calendar.component(.year, from: now)

        var totalsByMonth: [Int: Decimal] = [:]
        var totalsByClient: [UUID: Decimal] = [:]
        var dailyEarnings: [Date: Decimal] = [:]
        var yearToDate: Decimal = .zero
        var unsupportedCurrencyCount = 0

        for client in clients {
            for entry in client.entries {
                guard entry.isEarned else { continue }
                if !converter.canConvert(entry.currencyCode) {
                    unsupportedCurrencyCount += 1
                    continue
                }

                let base = converter.toBase(entry.amount, code: entry.currencyCode)
                let entryMonthKey = monthKey(entry.date, calendar: calendar)
                if comparisonKeys.contains(entryMonthKey) {
                    totalsByMonth[entryMonthKey, default: .zero] += base
                }
                if visibleKeys.contains(entryMonthKey) {
                    totalsByClient[client.id, default: .zero] += base
                }
                if calendar.component(.year, from: entry.date) == currentYear {
                    yearToDate += base
                }

                let start = calendar.startOfDay(for: entry.date)
                let rawEnd = entry.holdUntil.map { calendar.startOfDay(for: $0) } ?? start
                let end = max(start, rawEnd)
                let dayCount = max((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1)
                let perDay = base / Decimal(dayCount)
                var day = max(start, calendar.startOfDay(for: windowStart))
                let last = min(end, calendar.startOfDay(for: windowEnd))
                while day <= last {
                    dailyEarnings[day, default: .zero] += perDay
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
        }

        let monthlyIncome = visibleMonths.map { month in
            let key = monthKey(month, calendar: calendar)
            let previous = calendar.date(byAdding: .month, value: -1, to: month)
                .map { totalsByMonth[monthKey($0, calendar: calendar)] ?? .zero } ?? .zero
            return InsightsDashboardSnapshot.MonthPoint(
                month: month,
                total: totalsByMonth[key] ?? .zero,
                previousTotal: previous
            )
        }
        let clientTotals = clients.compactMap { client -> InsightsDashboardSnapshot.ClientTotal? in
            let total = totalsByClient[client.id] ?? .zero
            guard total > 0 else { return nil }
            return .init(id: client.id, name: client.name, colorHex: client.colorHex, total: total)
        }.sorted { $0.total > $1.total }

        let windowTotal = monthlyIncome.reduce(Decimal.zero) { $0 + $1.total }
        let activeMonthCount = monthlyIncome.count { $0.total > 0 }
        return InsightsDashboardSnapshot(
            windowMonths: count,
            months: visibleMonths,
            monthlyIncome: monthlyIncome,
            dailyEarnings: dailyEarnings,
            clientTotals: clientTotals,
            yearToDateTotal: yearToDate,
            averageMonth: activeMonthCount == 0 ? .zero : windowTotal / Decimal(activeMonthCount),
            bestMonth: windowTotal > 0 ? monthlyIncome.max { $0.total < $1.total } : nil,
            unsupportedCurrencyCount: unsupportedCurrencyCount
        )
    }

    nonisolated private func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    nonisolated private func monthKey(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        return (components.year ?? 0) * 12 + (components.month ?? 1) - 1
    }
}

/// Reads the dashboard's ledger rows on a private model actor before reducing
/// them into the Sendable snapshot consumed by `InsightsView`. Opening the
/// sheet can therefore show its loading state immediately even when the local
/// ledger has thousands of entries.
@ModelActor
actor InsightsDashboardLoader {
    func load(
        windowMonths: Int,
        converter: CurrencyConverter,
        now: Date = .now
    ) throws -> InsightsDashboardSnapshot {
        let storedClients = try modelContext.fetch(FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\Client.sortIndex)]
        ))
        let clientIDs = Set(storedClients.lazy.filter { !$0.isDeleted }.map(\.id))

        var entriesByClientID: [UUID: [InsightsDashboardInput.EntryRecord]] = [:]
        for entry in try modelContext.fetch(FetchDescriptor<Entry>()) {
            guard !entry.isDeleted,
                  let clientID = entry.client?.id,
                  clientIDs.contains(clientID) else { continue }
            entriesByClientID[clientID, default: []].append(.init(
                amount: entry.amount,
                currencyCode: entry.currencyCode,
                date: entry.date,
                holdUntil: entry.holdUntil,
                isEarned: entry.status.isIncludedInEarnedTotals
            ))
        }

        let records = storedClients.compactMap { client -> InsightsDashboardInput.ClientRecord? in
            guard !client.isDeleted else { return nil }
            return .init(
                id: client.id,
                name: client.name,
                colorHex: client.colorHex,
                entries: entriesByClientID[client.id, default: []]
            )
        }
        return InsightsDashboardInput(records: records, converter: converter)
            .dashboardSnapshot(windowMonths: windowMonths, now: now)
    }
}

/// Complete presentation state for one Insights period. Views read this value
/// directly, so selecting a day or chart bar never re-aggregates the ledger.
struct InsightsDashboardSnapshot: Sendable {
    /// The default dashboard window retained for callers that do not choose a
    /// period explicitly. The Insights screen may request 3, 6, or 12 months.
    static let chartMonthCount = 12
    static let heatmapMonthCount = 12

    struct MonthPoint: Identifiable, Sendable {
        let month: Date
        let total: Decimal
        let previousTotal: Decimal
        var id: Date { month }
        var change: Decimal { total - previousTotal }
    }

    struct ClientTotal: Identifiable, Sendable {
        let id: UUID
        let name: String
        let colorHex: String
        let total: Decimal
    }

    let windowMonths: Int
    /// The heatmap's months for the selected window, oldest first.
    let months: [Date]
    /// The chart's months for the selected window, oldest first.
    let monthlyIncome: [MonthPoint]
    let dailyEarnings: [Date: Decimal]
    let clientTotals: [ClientTotal]
    let yearToDateTotal: Decimal
    let averageMonth: Decimal
    let bestMonth: MonthPoint?
    let unsupportedCurrencyCount: Int
}

/// Pure income aggregation over the ledger: grouping and totals, the monthly
/// series and its month-over-month deltas, the daily-earnings heatmap, and the
/// pending queue. Every figure is in the base currency via the injected
/// `CurrencyConverter`; earned totals exclude canceled lines. Free of UI state
/// so it can be unit-tested directly — `AppModel` exposes thin forwarders.
///
/// `@MainActor` because it reads SwiftData model properties (`Client`/`Entry`),
/// matching the isolation this math already ran under inside `AppModel`.
@MainActor
struct Insights {
    let converter: CurrencyConverter
    var calendar: Calendar = .current

    // MARK: Grouping & totals

    func entries(of client: Client, in month: Date) -> [Entry] {
        client.entries
            .filter { sameMonth($0.date, month) }
            .sorted { $0.sortIndex == $1.sortIndex ? $0.createdAt > $1.createdAt : $0.sortIndex < $1.sortIndex }
    }

    func earnedEntries(of client: Client, in month: Date) -> [Entry] {
        entries(of: client, in: month).filter { $0.status.isIncludedInEarnedTotals }
    }

    func total(of client: Client, in month: Date) -> Decimal {
        // A running sum doesn't care about order, so skip the filtered-array
        // allocation and the sort that `earnedEntries` does — this runs per
        // client, per visible month, and (×6) on every summary refresh.
        client.entries.reduce(Decimal.zero) { sum, entry in
            guard entry.status.isIncludedInEarnedTotals, sameMonth(entry.date, month) else { return sum }
            return sum + converter.toBase(entry.amount, code: entry.currencyCode)
        }
    }

    func monthTotal(_ clients: [Client], in month: Date) -> Decimal {
        clients.reduce(Decimal.zero) { $0 + total(of: $1, in: month) }
    }

    // MARK: Daily heatmap

    // How a single line lands on the calendar: the base-currency amount it
    // contributes per day and the span of days it covers. A *held* line
    // spreads its amount evenly across every day from its own date through the
    // hold-release day (inclusive) — the money is "earning" across the wait —
    // while every other line lands wholly on its date.
    // swiftlint:disable:next large_tuple
    private func heatSpan(of entry: Entry) -> (start: Date, end: Date, perDay: Decimal, dayCount: Int) {
        let base = converter.toBase(entry.amount, code: entry.currencyCode)
        let start = calendar.startOfDay(for: entry.date)
        guard let hold = entry.holdUntil else { return (start, start, base, 1) }
        let end = calendar.startOfDay(for: hold)
        guard end > start else { return (start, start, base, 1) }
        let count = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return (start, end, base / Decimal(count), count)
    }

    /// The lines earning on `day`, largest slice first, each paired with the
    /// base-currency amount it contributes that day (a full amount, or one even
    /// slice of a held line). Powers the tapped-day breakdown.
    ///
    /// `candidates` is a superset supplied by the caller — see
    /// `dayContributionCandidates(on:in:)`. This used to walk every client's
    /// entries on every day tap.
    func dayContributions(on day: Date, candidates: [Entry]) -> [(entry: Entry, amount: Decimal, isHeldSlice: Bool)] {
        let target = calendar.startOfDay(for: day)
        var rows: [(entry: Entry, amount: Decimal, isHeldSlice: Bool)] = []
        for entry in candidates
        where !entry.isDeleted && entry.status.isIncludedInEarnedTotals {
            let span = heatSpan(of: entry)
            if target >= span.start && target <= span.end {
                rows.append((entry: entry, amount: span.perDay, isHeldSlice: span.dayCount > 1))
            }
        }
        return rows.sorted { $0.amount > $1.amount }
    }

    /// Every entry that could contribute to `day`, fetched in two scoped
    /// queries rather than by faulting the whole store:
    ///
    /// 1. lines dated on the day itself, and
    /// 2. lines dated earlier that carry a hold — a held line spreads its
    ///    amount across `date ... holdUntil`, so only these can reach forward.
    ///
    /// The hold set is bounded by how many held lines exist in history, which
    /// is a small fraction of the ledger. `dayContributions` then applies the
    /// exact span test to the union.
    static func dayContributionCandidates(on day: Date, in context: ModelContext) -> [Entry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let onTheDay = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        let heldFromEarlier = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.holdUntil != nil && $0.date < dayStart }
        )
        let sameDay = (try? context.fetch(onTheDay)) ?? []
        let held = (try? context.fetch(heldFromEarlier)) ?? []

        var seen = Set(sameDay.map(\.id))
        return sameDay + held.filter { seen.insert($0.id).inserted }
    }

    // MARK: Pending / outstanding

    /// Order in-progress lines by urgency: soonest `holdUntil` first (undated
    /// last), then by creation.
    ///
    /// The caller supplies the rows. This used to take `[Client]` and reach
    /// through `flatMap(\.entries)`, faulting the entire store to find the
    /// handful of outstanding lines; callers now pass a predicate-scoped fetch.
    static func sortedByUrgency(_ entries: [Entry]) -> [Entry] {
        // `isDeleted`, not `isInvalidated` — same reason as `ledgerSnapshot`:
        // it reads only registration metadata, so a free-standing fixture with
        // no context yet is not mistaken for a dead row.
        entries
            .filter { !$0.isDeleted && $0.status == .inProgress }
            .sorted { a, b in
                switch (a.holdUntil, b.holdUntil) {
                case let (l?, r?): return l == r ? a.createdAt < b.createdAt : l < r
                case (_?, nil): return true   // dated before undated
                case (nil, _?): return false
                case (nil, nil): return a.createdAt < b.createdAt
                }
            }
    }

    /// An in-progress line whose hold date is already in the past.
    func isOverdue(_ entry: Entry) -> Bool {
        guard entry.status == .inProgress, let hold = entry.holdUntil else { return false }
        return hold < calendar.startOfDay(for: .now)
    }

    /// Months containing at least one visible entry (newest first), always including this month.
    func monthsWithData(_ clients: [Client]) -> [Date] {
        var set = Set<Date>()
        for c in clients {
            for e in c.entries {
                set.insert(DateFormat.monthStart(of: e.date))
            }
        }
        set.insert(DateFormat.monthStart(of: .now))
        return set.sorted(by: >)
    }

    private func sameMonth(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    // MARK: Ledger snapshot (single-pass aggregation)

    /// Integer key for the month containing `date` (`year * 12 + month`).
    /// Bucketing by this key costs one `dateComponents` call per entry, where
    /// the per-month filters above cost a two-date `Calendar` granularity
    /// comparison per entry *per month* — the difference between O(entries)
    /// and O(months × entries) every time the ledger row model rebuilds.
    nonisolated static func monthKey(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return (parts.year ?? 0) * 12 + ((parts.month ?? 1) - 1)
    }

    /// Everything the ledger list and its summary header read, aggregated in
    /// one pass over the entries: months with data, each client's sorted
    /// entries per month, and earned totals per client-month and per month.
    /// Built fresh per body evaluation — cheap enough that no cross-render
    /// cache (and no cache-invalidation bug surface) is needed.
    struct LedgerSnapshot {
        /// Months with visible ledger content (newest first), always including
        /// the current month. Entry rows provide the normal months and note
        /// events add their otherwise-empty months. A windowed snapshot lists
        /// only the materialized window; older ones materialize incrementally.
        let months: [Date]
        /// Earned base-currency total per month key (canceled excluded).
        let earnedTotalByMonth: [Int: Decimal]
        /// Whether any client has any entry — the ledger's empty-state check,
        /// counted here so the view never faults entry relationships for it.
        let hasEntries: Bool
        /// Number of in-progress lines — the More menu's "Pending (N)" label.
        let pendingCount: Int
        /// Whether entries exist before the first month in `months` — drives
        /// the ledger's load-older sentinel.
        let hasOlderMonths: Bool
        private let entriesByClientMonth: [ClientMonth: [Entry]]
        private let earnedTotalByClientMonth: [ClientMonth: Decimal]

        fileprivate init(months: [Date],
                         earnedTotalByMonth: [Int: Decimal],
                         hasEntries: Bool,
                         pendingCount: Int,
                         hasOlderMonths: Bool,
                         entriesByClientMonth: [ClientMonth: [Entry]],
                         earnedTotalByClientMonth: [ClientMonth: Decimal]) {
            self.months = months
            self.earnedTotalByMonth = earnedTotalByMonth
            self.hasEntries = hasEntries
            self.pendingCount = pendingCount
            self.hasOlderMonths = hasOlderMonths
            self.entriesByClientMonth = entriesByClientMonth
            self.earnedTotalByClientMonth = earnedTotalByClientMonth
        }

        struct ClientMonth: Hashable {
            let client: UUID
            let month: Int
        }

        func key(for month: Date) -> Int { Insights.monthKey(of: month) }

        func hasEntries(_ client: Client, monthKey: Int) -> Bool {
            entriesByClientMonth[ClientMonth(client: client.id, month: monthKey)] != nil
        }

        /// The client's entries in the month, ledger row order — matches
        /// `Insights.entries(of:in:)`.
        func entries(of client: Client, monthKey: Int) -> [Entry] {
            entriesByClientMonth[ClientMonth(client: client.id, month: monthKey)] ?? []
        }

        /// Earned total for one client in one month — matches `Insights.total(of:in:)`.
        func total(of client: Client, monthKey: Int) -> Decimal {
            earnedTotalByClientMonth[ClientMonth(client: client.id, month: monthKey)] ?? .zero
        }

        /// Earned total across clients for one month — matches `Insights.monthTotal(_:in:)`.
        func monthTotal(monthKey: Int) -> Decimal {
            earnedTotalByMonth[monthKey] ?? .zero
        }

    }

    /// Full snapshot over every client's entries — the search path, the
    /// ledger's one-off action fallback, and the unit tests use this.
    func ledgerSnapshot(_ clients: [Client]) -> LedgerSnapshot {
        // `isDeleted` (not `isInvalidated`) on purpose: it reads only
        // registration metadata, and free-standing models in unit tests have
        // no context yet — `isInvalidated` would treat the fixture as dead.
        var rows: [(owner: Client, entry: Entry)] = []
        for client in clients where !client.isDeleted {
            for entry in client.entries {
                rows.append((client, entry))
            }
        }
        return buildLedgerSnapshot(rows: rows, hasAnyEntries: nil,
                                   pendingCount: nil, hasOlderMonths: false,
                                   additionalMonths: [])
    }

    /// Windowed snapshot: `entries` are just the rows inside the ledger's
    /// visible month window (a date-scoped fetch, so launch never faults the
    /// whole table), while the whole-store facts arrive from cheap SQL counts
    /// at the call site. Owners resolve through the store-maintained
    /// `entry.client` relationship; orphaned rows are skipped, as before.
    func ledgerSnapshot(windowed entries: [Entry],
                        hasOlderMonths: Bool,
                        hasAnyEntries: Bool,
                        pendingCount: Int,
                        additionalMonths: [Date] = []) -> LedgerSnapshot {
        let rows = entries.compactMap { entry in
            entry.client.map { (owner: $0, entry: entry) }
        }
        return buildLedgerSnapshot(rows: rows, hasAnyEntries: hasAnyEntries,
                                   pendingCount: pendingCount, hasOlderMonths: hasOlderMonths,
                                   additionalMonths: additionalMonths)
    }

    private func buildLedgerSnapshot(rows: [(owner: Client, entry: Entry)],
                                     hasAnyEntries: Bool?,
                                     pendingCount pendingCountOverride: Int?,
                                     hasOlderMonths: Bool,
                                     additionalMonths: [Date]) -> LedgerSnapshot {
        var entriesByClientMonth: [LedgerSnapshot.ClientMonth: [Entry]] = [:]
        var earnedTotalByClientMonth: [LedgerSnapshot.ClientMonth: Decimal] = [:]
        var earnedTotalByMonth: [Int: Decimal] = [:]
        var monthKeys = Set<Int>()
        var pendingCount = 0

        // A sync pull can delete models mid-render; skip those the same way
        // the ledger's row views do.
        for (owner, entry) in rows where !entry.isDeleted && !owner.isDeleted {
            let key = LedgerSnapshot.ClientMonth(client: owner.id,
                                                 month: Self.monthKey(of: entry.date, calendar: calendar))
            monthKeys.insert(key.month)
            entriesByClientMonth[key, default: []].append(entry)
            let status = entry.status
            if status == .inProgress { pendingCount += 1 }
            if status.isIncludedInEarnedTotals {
                let base = converter.toBase(entry.amount, code: entry.currencyCode)
                earnedTotalByClientMonth[key, default: .zero] += base
                earnedTotalByMonth[key.month, default: .zero] += base
            }
        }
        for key in entriesByClientMonth.keys {
            entriesByClientMonth[key]?.sort {
                $0.sortIndex == $1.sortIndex ? $0.createdAt > $1.createdAt : $0.sortIndex < $1.sortIndex
            }
        }

        for month in additionalMonths {
            monthKeys.insert(Self.monthKey(of: month, calendar: calendar))
        }
        monthKeys.insert(Self.monthKey(of: .now, calendar: calendar))
        let months = monthKeys.sorted(by: >).compactMap { key in
            calendar.date(from: DateComponents(year: key / 12, month: key % 12 + 1))
        }
        return LedgerSnapshot(months: months,
                              earnedTotalByMonth: earnedTotalByMonth,
                              hasEntries: hasAnyEntries ?? !entriesByClientMonth.isEmpty,
                              pendingCount: pendingCountOverride ?? pendingCount,
                              hasOlderMonths: hasOlderMonths,
                              entriesByClientMonth: entriesByClientMonth,
                              earnedTotalByClientMonth: earnedTotalByClientMonth)
    }
}
