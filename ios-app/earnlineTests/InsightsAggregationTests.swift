import Foundation
import SwiftData
import Testing
@testable import earnline

/// Direct coverage for the `Insights` aggregation type: the single-pass
/// `LedgerSnapshot` (totals per client-month, month list, row order, and the
/// windowed variant's whole-store facts), the pending-queue ordering, and
/// overdue detection.
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
        let snapshot = insights().ledgerSnapshot([a, b])
        #expect(snapshot.monthTotal(monthKey: snapshot.key(for: thisMonth)) == 150)
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

        let pending = Insights.sortedByUrgency(client.entries)
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

    @Test func snapshotMonthsAlwaysIncludeThisMonthNewestFirst() {
        let client = Client(name: "Acme")
        client.entries = [Entry(amount: 10, task: "old", date: monthsAgo(2), status: .paid)]
        let months = insights().ledgerSnapshot([client]).months
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

    @Test func ledgerRowsCarryTheirRepresentedMonthWithoutReadingGeometry() {
        let month = DateFormat.monthStart(of: date(2025, 12, 22))
        let entry = Entry(amount: 100, task: "Year-end work", date: date(2025, 12, 22))
        let row = LedgerRow.entry(entry, month)

        #expect(row.representedMonth == month)
        #expect(row.id.representedMonth == month)
    }

    @Test func ledgerPrefetchCrossesJanuaryWithoutMissingTheTrendBoundary() {
        let january = DateFormat.monthStart(of: date(2026, 1, 15))
        let august = DateFormat.monthStart(of: date(2025, 8, 15))

        #expect(LedgerWindowPrefetch.needsExtension(
            for: january,
            windowStart: january,
            hasOlderMonths: true
        ))
        #expect(!LedgerWindowPrefetch.needsExtension(
            for: january,
            windowStart: august,
            hasOlderMonths: true
        ))
        #expect(!LedgerWindowPrefetch.needsExtension(
            for: january,
            windowStart: january,
            hasOlderMonths: false
        ))
    }

    @Test func ledgerSnapshotBucketsTotalsByClientAndMonth() {
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

        // Every month with a row is present, newest first, plus this month.
        #expect(snapshot.months.first == thisMonth)
        #expect(snapshot.months.contains(DateFormat.monthStart(of: monthsAgo(2))))
        // Paid + in-progress across both clients; the canceled line is excluded.
        #expect(snapshot.monthTotal(monthKey: nowKey) == 150)
        #expect(snapshot.monthTotal(monthKey: oldKey) == 40)
        #expect(snapshot.total(of: a, monthKey: nowKey) == 100)
        #expect(snapshot.total(of: b, monthKey: nowKey) == 50)
        // Canceled lines appear in the rows but not in earned totals.
        #expect(snapshot.entries(of: a, monthKey: nowKey).count == 2)
        // Months without data read as zero, not as a crash or a miss.
        #expect(snapshot.monthTotal(monthKey: snapshot.key(for: monthsAgo(1))) == 0)
        #expect(!snapshot.hasEntries(b, monthKey: oldKey))
    }

    /// Ledger row order: ascending `sortIndex`, newest-created first on a tie.
    @Test func ledgerSnapshotOrdersEntriesBySortIndexThenNewestCreated() {
        let ins = insights()
        let client = Client(name: "Acme")
        let early = Entry(amount: 1, task: "early", date: thisMonth,
                          sortIndex: 1, createdAt: date(2026, 1, 1))
        let late = Entry(amount: 2, task: "late", date: thisMonth,
                         sortIndex: 0, createdAt: date(2026, 1, 2))
        let tie = Entry(amount: 3, task: "tie", date: thisMonth,
                        sortIndex: 1, createdAt: date(2026, 1, 3))
        client.entries = [early, late, tie]

        let snapshot = ins.ledgerSnapshot([client])
        let ordered = snapshot.entries(of: client, monthKey: snapshot.key(for: thisMonth)).map(\.task)
        // sortIndex 0 leads; the two index-1 rows tie and fall back to createdAt
        // descending, so the newer "tie" precedes "early".
        #expect(ordered == ["late", "tie", "early"])
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
        #expect(windowed.total(of: client, monthKey: key) == 100)
        #expect(windowed.monthTotal(monthKey: key) == 100)
        #expect(windowed.entries(of: client, monthKey: key).map(\.task) == ["recent"])
        // The old month is outside the window: no rows, no month.
        #expect(!windowed.months.contains(DateFormat.monthStart(of: monthsAgo(9))))
        #expect(windowed.hasOlderMonths)
        #expect(windowed.hasEntries)
        #expect(windowed.pendingCount == 7)
    }

    @Test func windowedLedgerSnapshotIncludesAnOtherwiseEmptyEventMonth() {
        let ins = insights()
        let client = Client(name: "Acme")
        let recent = Entry(amount: 100, task: "recent", date: thisMonth, status: .paid)
        recent.client = client
        let noteMonth = monthsAgo(3)

        let snapshot = ins.ledgerSnapshot(
            windowed: [recent],
            hasOlderMonths: false,
            hasAnyEntries: true,
            pendingCount: 0,
            additionalMonths: [noteMonth]
        )

        let normalizedNoteMonth = DateFormat.monthStart(of: noteMonth)
        #expect(snapshot.months.contains(normalizedNoteMonth))
        #expect(snapshot.monthTotal(monthKey: snapshot.key(for: normalizedNoteMonth)) == .zero)
        #expect(snapshot.months == snapshot.months.sorted(by: >))
    }

    @Test func fullLedgerSnapshotReportsNoOlderMonths() {
        let client = Client(name: "Acme")
        client.entries = [Entry(amount: 10, task: "only", date: monthsAgo(3), status: .inProgress)]
        let snapshot = insights().ledgerSnapshot([client])
        #expect(!snapshot.hasOlderMonths) // the full pass materializes everything
        #expect(snapshot.pendingCount == 1)
        #expect(snapshot.hasEntries)
    }

    // MARK: Dashboard snapshot (off-main presentation data)

    @Test func dashboardSnapshotBuildsAllPresentationFiguresInOnePass() {
        let now = date(2026, 7, 11)
        let previousMonth = date(2026, 6, 15)
        let acme = Client(name: "Acme", colorHex: "#0088FF")
        let northstar = Client(name: "Northstar", colorHex: "#7B00FF")
        let unsupported = Client(name: "Unsupported")
        acme.entries = [
            Entry(amount: 300, task: "held", date: date(2026, 7, 10),
                  holdUntil: date(2026, 7, 12), status: .inProgress),
            Entry(amount: 999, currencyCode: "EUR", task: "canceled", date: now, status: .canceled),
        ]
        northstar.entries = [
            Entry(amount: 8_300, currencyCode: "RUB", task: "prior", date: previousMonth, status: .paid),
        ]
        unsupported.entries = [
            Entry(amount: 500, currencyCode: "EUR", task: "unknown", date: now, status: .paid),
        ]

        let input = InsightsDashboardInput(
            clients: [acme, northstar, unsupported],
            converter: CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 83)
        )
        let snapshot = input.dashboardSnapshot(now: now)

        #expect(snapshot.monthlyIncome.count == InsightsDashboardSnapshot.chartMonthCount)
        #expect(snapshot.months.count == InsightsDashboardSnapshot.heatmapMonthCount)
        #expect(snapshot.monthlyIncome.last?.total == 300)
        #expect(snapshot.monthlyIncome.last?.previousTotal == 100)
        #expect(snapshot.clientTotals.map(\.name) == ["Acme", "Northstar"])
        #expect(snapshot.unsupportedCurrencyCount == 1)
        #expect(snapshot.yearToDateTotal == 400)
        #expect(snapshot.dailyEarnings[Calendar.current.startOfDay(for: date(2026, 7, 11))] == 100)
        #expect(snapshot.bestMonth?.total == 300)
        #expect(snapshot.averageMonth == 200)
    }

    @Test func dashboardLoaderFetchesAndCopiesTheLedgerOnItsModelActor() async throws {
        let container = try ModelContainer(
            for: Client.self, Entry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let client = Client(name: "Acme")
        let entry = Entry(amount: 300, task: "Launch", date: date(2026, 7, 10), status: .paid)
        entry.client = client
        context.insert(client)
        context.insert(entry)
        try context.save()

        let snapshot = try await InsightsDashboardLoader(modelContainer: container).load(
            windowMonths: 1,
            converter: CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 83),
            now: date(2026, 7, 11)
        )

        #expect(snapshot.monthlyIncome.last?.total == 300)
        #expect(snapshot.clientTotals.map(\.name) == ["Acme"])
    }

    // MARK: Client profile snapshot

    @Test func clientDetailSnapshotBuildsAllBreakdownsInOnePass() {
        let targetID = UUID()
        let otherID = UUID()
        let input = ClientDetailSnapshotInput(
            clientID: targetID,
            entries: [
                .init(clientID: targetID, amount: 300, currencyCode: "USD", project: "Launch",
                      date: date(2026, 7, 10), statusRaw: EntryStatus.paid.rawValue),
                .init(clientID: targetID, amount: 8_300, currencyCode: "RUB", project: "Launch",
                      date: date(2026, 6, 10), statusRaw: EntryStatus.inProgress.rawValue),
                .init(clientID: targetID, amount: 999, currencyCode: "USD", project: "Ignored",
                      date: date(2026, 7, 10), statusRaw: EntryStatus.canceled.rawValue),
                .init(clientID: otherID, amount: 600, currencyCode: "USD", project: nil,
                      date: date(2026, 7, 10), statusRaw: EntryStatus.paid.rawValue),
            ],
            converter: CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 83)
        )

        let snapshot = input.snapshot(now: date(2026, 7, 11))

        #expect(snapshot.total == 400)
        #expect(snapshot.averagePerActiveMonth == 200)
        #expect(snapshot.shareOfIncome == 0.4)
        #expect(snapshot.transactionCount == 3)
        #expect(snapshot.months.count == 12)
        #expect(snapshot.months.last?.total == 300)
        #expect(snapshot.statusTotals.map(\.count) == [1, 1, 1])
        #expect(snapshot.projectTotals.count == 1)
        #expect(snapshot.projectTotals.first?.name == "Launch")
        #expect(snapshot.projectTotals.first?.count == 2)
        #expect(snapshot.projectTotals.first?.total == 400)
    }

    @Test func clientDetailSnapshotStaysLinearAtStressLedgerSize() {
        let targetID = UUID()
        let otherID = UUID()
        let entries = (0..<6_000).map { index in
            ClientDetailSnapshotInput.EntryRecord(
                clientID: index.isMultiple(of: 8) ? targetID : otherID,
                amount: Decimal(index % 900 + 1),
                currencyCode: "USD",
                project: "Project \(index % 12)",
                date: Date(timeIntervalSinceReferenceDate: TimeInterval(index * 86_400)),
                statusRaw: EntryStatus.paid.rawValue
            )
        }
        let input = ClientDetailSnapshotInput(
            clientID: targetID,
            entries: entries,
            converter: CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 83)
        )

        let clock = ContinuousClock()
        let duration = clock.measure {
            _ = input.snapshot(now: date(2026, 7, 11))
        }

        #expect(duration < .seconds(1))
    }
}
