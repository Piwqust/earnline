import Foundation

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

    func clientsWithEntries(_ clients: [Client], in month: Date) -> [Client] {
        clients
            .filter { !entries(of: $0, in: month).isEmpty }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func monthTotal(_ clients: [Client], in month: Date) -> Decimal {
        clients.reduce(Decimal.zero) { $0 + total(of: $1, in: month) }
    }

    // MARK: Trend series

    /// Earned base-currency total for each of the last `lastNMonths` months,
    /// oldest first. Months with no data come back as 0 so the chart is continuous.
    func monthlySeries(_ clients: [Client], lastNMonths: Int = 12) -> [(month: Date, total: Decimal)] {
        let thisMonth = DateFormat.monthStart(of: .now)
        return (0..<max(lastNMonths, 1)).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return (month: month, total: monthTotal(clients, in: month))
        }
    }

    /// Every client that earned over the last `lastNMonths` months, highest
    /// first, dropping clients with nothing earned — the full breakdown behind
    /// the Top clients composition bar.
    func clientTotals(_ clients: [Client], lastNMonths: Int = 12) -> [(client: Client, total: Decimal)] {
        let months = monthlySeries(clients, lastNMonths: lastNMonths).map(\.month)
        return clients
            .map { client in
                (client: client, total: months.reduce(Decimal.zero) { $0 + total(of: client, in: $1) })
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    /// The `limit` highest-earning clients over the window.
    func topClients(_ clients: [Client], lastNMonths: Int = 12, limit: Int = 3) -> [(client: Client, total: Decimal)] {
        Array(clientTotals(clients, lastNMonths: lastNMonths).prefix(limit))
    }

    /// Month-over-month change in earned revenue across the last `lastNMonths`
    /// months: each month's earned total minus the prior month's. An extra
    /// leading month is fetched so the first bar has a real baseline.
    func monthlyDeltas(_ clients: [Client], lastNMonths: Int = 12) -> [(month: Date, delta: Decimal, total: Decimal)] {
        let series = monthlySeries(clients, lastNMonths: lastNMonths + 1)
        guard series.count >= 2 else {
            return series.map { (month: $0.month, delta: $0.total, total: $0.total) }
        }
        return (1..<series.count).map { index in
            (month: series[index].month,
             delta: series[index].total - series[index - 1].total,
             total: series[index].total)
        }
    }

    /// Straight-line month-end projection for the running month: the earned
    /// total so far scaled up to the full month. Nil while there's nothing to
    /// extrapolate — no earnings yet, or the first two days of a month (one
    /// early invoice would project an absurd figure).
    nonisolated static func monthPace(total: Decimal,
                                      now: Date = .now,
                                      calendar: Calendar = .current) -> Decimal? {
        guard total > 0 else { return nil }
        let day = calendar.component(.day, from: now)
        guard day >= 3,
              let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
        return (total / Decimal(day) * Decimal(daysInMonth)).rounded()
    }

    // MARK: Daily heatmap

    /// How a single line lands on the calendar: the base-currency amount it
    /// contributes per day and the span of days it covers. A *held* line
    /// spreads its amount evenly across every day from its own date through the
    /// hold-release day (inclusive) — the money is "earning" across the wait —
    /// while every other line lands wholly on its date.
    private func heatSpan(of entry: Entry) -> (start: Date, end: Date, perDay: Decimal, dayCount: Int) {
        let base = converter.toBase(entry.amount, code: entry.currencyCode)
        let start = calendar.startOfDay(for: entry.date)
        guard let hold = entry.holdUntil else { return (start, start, base, 1) }
        let end = calendar.startOfDay(for: hold)
        guard end > start else { return (start, start, base, 1) }
        let count = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return (start, end, base / Decimal(count), count)
    }

    /// Earned base-currency amount for each calendar day in `[startDay, endDay]`,
    /// with held lines distributed evenly over their span. Canceled lines are
    /// excluded; days with nothing earned are simply absent from the result.
    /// Keys are start-of-day, matching what the heatmap looks up.
    func dailyEarnings(_ clients: [Client], from startDay: Date, through endDay: Date) -> [Date: Decimal] {
        let lo = calendar.startOfDay(for: startDay)
        let hi = calendar.startOfDay(for: endDay)
        guard lo <= hi else { return [:] }
        var map: [Date: Decimal] = [:]
        for client in clients {
            for entry in client.entries where entry.status.isIncludedInEarnedTotals {
                let span = heatSpan(of: entry)
                var day = max(span.start, lo)
                let last = min(span.end, hi)
                while day <= last {
                    map[day, default: .zero] += span.perDay
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
        }
        return map
    }

    /// The lines earning on `day`, largest slice first, each paired with the
    /// base-currency amount it contributes that day (a full amount, or one even
    /// slice of a held line). Powers the tapped-day breakdown.
    func dayContributions(on day: Date, clients: [Client]) -> [(entry: Entry, amount: Decimal, isHeldSlice: Bool)] {
        let target = calendar.startOfDay(for: day)
        var rows: [(entry: Entry, amount: Decimal, isHeldSlice: Bool)] = []
        for client in clients {
            for entry in client.entries where entry.status.isIncludedInEarnedTotals {
                let span = heatSpan(of: entry)
                if target >= span.start && target <= span.end {
                    rows.append((entry: entry, amount: span.perDay, isHeldSlice: span.dayCount > 1))
                }
            }
        }
        return rows.sorted { $0.amount > $1.amount }
    }

    // MARK: Pending / outstanding

    /// All in-progress lines, soonest `holdUntil` first (undated last), then by
    /// creation. These are the lines that still need follow-up.
    func pendingEntries(_ clients: [Client]) -> [Entry] {
        clients
            .flatMap(\.entries)
            .filter { $0.status == .inProgress }
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
        /// Months with at least one entry (newest first), always including the
        /// current month — same contract as `monthsWithData`. A windowed
        /// snapshot lists only the window's months; older ones materialize
        /// when the ledger extends its window.
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

    /// Earned base-currency totals for one client, bucketed by month key —
    /// the client-detail page's chart and stat source. One pass over the
    /// client's entries, like `ledgerSnapshot`.
    func earnedTotalsByMonth(of client: Client) -> [Int: Decimal] {
        var totals: [Int: Decimal] = [:]
        for entry in client.entries
        where !entry.isDeleted && entry.status.isIncludedInEarnedTotals {
            totals[Self.monthKey(of: entry.date, calendar: calendar), default: .zero] +=
                converter.toBase(entry.amount, code: entry.currencyCode)
        }
        return totals
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
                                   pendingCount: nil, hasOlderMonths: false)
    }

    /// Windowed snapshot: `entries` are just the rows inside the ledger's
    /// visible month window (a date-scoped fetch, so launch never faults the
    /// whole table), while the whole-store facts arrive from cheap SQL counts
    /// at the call site. Owners resolve through the store-maintained
    /// `entry.client` relationship; orphaned rows are skipped, as before.
    func ledgerSnapshot(windowed entries: [Entry],
                        hasOlderMonths: Bool,
                        hasAnyEntries: Bool,
                        pendingCount: Int) -> LedgerSnapshot {
        let rows = entries.compactMap { entry in
            entry.client.map { (owner: $0, entry: entry) }
        }
        return buildLedgerSnapshot(rows: rows, hasAnyEntries: hasAnyEntries,
                                   pendingCount: pendingCount, hasOlderMonths: hasOlderMonths)
    }

    private func buildLedgerSnapshot(rows: [(owner: Client, entry: Entry)],
                                     hasAnyEntries: Bool?,
                                     pendingCount pendingCountOverride: Int?,
                                     hasOlderMonths: Bool) -> LedgerSnapshot {
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
