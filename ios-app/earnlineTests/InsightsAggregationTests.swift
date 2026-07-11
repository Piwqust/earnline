import Foundation
import Testing
@testable import earnline

/// Direct coverage for the extracted `Insights` aggregation type. The existing
/// `InsightsTests` drive it through `AppModel`'s forwarders; these exercise the
/// value type itself and fill gaps the old suite didn't cover — month-over-month
/// deltas, the pending-queue ordering, overdue detection, and `monthsWithData`.
@MainActor
struct InsightsAggregationTests {
    private func insights(rate: Double = 100) -> Insights {
        Insights(converter: CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: rate))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var thisMonth: Date { DateFormat.monthStart(of: .now) }
    private func monthsAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -n, to: thisMonth)!
    }

    @Test func monthTotalSumsEarnedAcrossClientsExcludingCanceled() {
        let a = Client(name: "A")
        let b = Client(name: "B")
        a.entries = [
            Entry(amount: 100, task: "paid", date: thisMonth, status: .paid),
            Entry(amount: 999, task: "canceled", date: thisMonth, status: .canceled),
        ]
        b.entries = [Entry(amount: 50, task: "progress", date: thisMonth, status: .inProgress)]
        #expect(insights().monthTotal([a, b], in: thisMonth) == 150)
    }

    @Test func clientTotalsDropZeroEarnersAndSortDescending() {
        let a = Client(name: "A")
        let b = Client(name: "B")
        let c = Client(name: "C")
        a.entries = [Entry(amount: 100, task: "x", date: thisMonth, status: .paid)]
        b.entries = [Entry(amount: 300, task: "y", date: thisMonth, status: .paid)]
        c.entries = [Entry(amount: 999, task: "z", date: thisMonth, status: .canceled)] // nothing earned

        let totals = insights().clientTotals([a, b, c], lastNMonths: 3)
        #expect(totals.map(\.client.name) == ["B", "A"]) // C dropped, sorted desc
        #expect(totals.first?.total == 300)
    }

    @Test func monthlyDeltasAreMonthOverMonthChange() {
        let client = Client(name: "Acme")
        client.entries = [
            Entry(amount: 100, task: "last", date: monthsAgo(1), status: .paid),
            Entry(amount: 250, task: "now", date: thisMonth, status: .paid),
        ]
        let deltas = insights().monthlyDeltas([client], lastNMonths: 2)
        #expect(deltas.count == 2)
        // Last bar: this month (250) minus last month (100) = +150.
        #expect(deltas.last?.delta == 150)
        #expect(deltas.last?.total == 250)
    }

    @Test func pendingEntriesOrderDatedBeforeUndatedThenBySoonestHold() {
        let client = Client(name: "Acme")
        let soon = Entry(amount: 10, task: "soon", date: thisMonth,
                         holdUntil: date(2026, 7, 10), status: .inProgress)
        let later = Entry(amount: 20, task: "later", date: thisMonth,
                          holdUntil: date(2026, 8, 10), status: .inProgress)
        let undated = Entry(amount: 30, task: "undated", date: thisMonth, status: .inProgress)
        let paid = Entry(amount: 40, task: "paid", date: thisMonth, status: .paid) // excluded
        client.entries = [undated, later, soon, paid]

        let pending = insights().pendingEntries([client])
        #expect(pending.map(\.task) == ["soon", "later", "undated"]) // dated-soonest first, undated last
    }

    @Test func isOverdueOnlyForPastHeldInProgressLines() {
        let ins = insights()
        let overdue = Entry(amount: 10, task: "od", date: date(2020, 1, 1),
                            holdUntil: date(2020, 1, 2), status: .inProgress)
        let future = Entry(amount: 10, task: "future", date: thisMonth,
                           holdUntil: date(2999, 1, 1), status: .inProgress)
        let paidPast = Entry(amount: 10, task: "paid", date: date(2020, 1, 1),
                             holdUntil: date(2020, 1, 2), status: .paid)
        #expect(ins.isOverdue(overdue))
        #expect(!ins.isOverdue(future))
        #expect(!ins.isOverdue(paidPast)) // only in-progress lines can be overdue
    }

    @Test func monthsWithDataAlwaysIncludesThisMonthNewestFirst() {
        let client = Client(name: "Acme")
        client.entries = [Entry(amount: 10, task: "old", date: monthsAgo(2), status: .paid)]
        let months = insights().monthsWithData([client])
        #expect(months.first == thisMonth)           // this month always present, newest first
        #expect(months.contains(DateFormat.monthStart(of: monthsAgo(2))))
        #expect(months == months.sorted(by: >))       // strictly descending
    }

    // MARK: Ledger snapshot (single-pass aggregation)

    @Test func monthKeyDistinguishesMonthsAcrossYearBoundaries() {
        #expect(Insights.monthKey(of: date(2025, 12, 31)) != Insights.monthKey(of: date(2026, 1, 1)))
        #expect(Insights.monthKey(of: date(2026, 7, 1)) == Insights.monthKey(of: date(2026, 7, 31)))
        // Adjacent months are adjacent keys, including over the year boundary.
        #expect(Insights.monthKey(of: date(2026, 1, 15)) - Insights.monthKey(of: date(2025, 12, 15)) == 1)
    }

    @Test func ledgerSnapshotMatchesPerMonthAggregation() {
        let ins = insights()
        let a = Client(name: "A")
        let b = Client(name: "B")
        a.entries = [
            Entry(amount: 100, task: "now-paid", date: thisMonth, status: .paid),
            Entry(amount: 999, task: "now-canceled", date: thisMonth, status: .canceled),
            Entry(amount: 40, task: "old", date: monthsAgo(2), status: .paid),
        ]
        b.entries = [Entry(amount: 50, task: "progress", date: thisMonth, status: .inProgress)]

        let snapshot = ins.ledgerSnapshot([a, b])
        let nowKey = snapshot.key(for: thisMonth)
        let oldKey = snapshot.key(for: monthsAgo(2))

        // Same months contract as monthsWithData.
        #expect(snapshot.months == ins.monthsWithData([a, b]))
        // Same totals as the per-month sweeps.
        #expect(snapshot.monthTotal(monthKey: nowKey) == ins.monthTotal([a, b], in: thisMonth))
        #expect(snapshot.monthTotal(monthKey: oldKey) == ins.monthTotal([a, b], in: monthsAgo(2)))
        #expect(snapshot.total(of: a, monthKey: nowKey) == ins.total(of: a, in: thisMonth))
        // Canceled lines appear in the rows but not in earned totals.
        #expect(snapshot.entries(of: a, monthKey: nowKey).count == 2)
        #expect(snapshot.monthTotal(monthKey: nowKey) == 150)
        // Months without data read as zero, not as a crash or a miss.
        #expect(snapshot.monthTotal(monthKey: snapshot.key(for: monthsAgo(1))) == 0)
        #expect(!snapshot.hasEntries(b, monthKey: oldKey))
    }

    @Test func ledgerSnapshotOrdersEntriesLikeEntriesOf() {
        let ins = insights()
        let client = Client(name: "Acme")
        let early = Entry(amount: 1, task: "early", date: thisMonth, sortIndex: 1)
        let late = Entry(amount: 2, task: "late", date: thisMonth, sortIndex: 0)
        let tie = Entry(amount: 3, task: "tie", date: thisMonth, sortIndex: 1)
        client.entries = [early, late, tie]

        let snapshot = ins.ledgerSnapshot([client])
        let fromSnapshot = snapshot.entries(of: client, monthKey: snapshot.key(for: thisMonth)).map(\.task)
        let fromFilter = ins.entries(of: client, in: thisMonth).map(\.task)
        #expect(fromSnapshot == fromFilter)
        #expect(fromSnapshot.first == "late") // sortIndex 0 leads
    }

    @Test func windowedLedgerSnapshotMatchesFullAggregationForWindowMonths() {
        let ins = insights()
        let client = Client(name: "Acme")
        let recent = Entry(amount: 100, task: "recent", date: thisMonth, status: .paid)
        let old = Entry(amount: 40, task: "old", date: monthsAgo(9), status: .paid)
        client.entries = [recent, old]
        // The windowed variant resolves owners through `entry.client`; a real
        // store maintains the inverse, free-standing fixtures set it directly.
        recent.client = client
        old.client = client

        // The window carries only the recent entry; the whole-store facts
        // (any entries at all, pending count, older months) come from counts.
        let windowed = ins.ledgerSnapshot(windowed: [recent],
                                          hasOlderMonths: true,
                                          hasAnyEntries: true,
                                          pendingCount: 7)
        let key = windowed.key(for: thisMonth)
        #expect(windowed.total(of: client, monthKey: key) == ins.total(of: client, in: thisMonth))
        #expect(windowed.monthTotal(monthKey: key) == 100)
        #expect(windowed.entries(of: client, monthKey: key).map(\.task) == ["recent"])
        // The old month is outside the window: no rows, no month.
        #expect(!windowed.months.contains(DateFormat.monthStart(of: monthsAgo(9))))
        #expect(windowed.hasOlderMonths)
        #expect(windowed.hasEntries)
        #expect(windowed.pendingCount == 7)
    }

    @Test func fullLedgerSnapshotReportsNoOlderMonths() {
        let client = Client(name: "Acme")
        client.entries = [Entry(amount: 10, task: "only", date: monthsAgo(3), status: .inProgress)]
        let snapshot = insights().ledgerSnapshot([client])
        #expect(!snapshot.hasOlderMonths) // the full pass materializes everything
        #expect(snapshot.pendingCount == 1)
        #expect(snapshot.hasEntries)
    }
}
