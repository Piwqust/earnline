import Foundation
import SwiftData
import Testing
@testable import earnline

@MainActor
struct LedgerSnapshotCacheTests {
    /// Containers must outlive the context they hand out, so every test holds
    /// one for its duration.
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let app: AppModel
        let suite: String
    }

    private func makeFixture() throws -> Fixture {
        let suite = "earnline-snapshot-cache-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let container = try ModelContainer(
            for: Client.self, Entry.self, Heading.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Fixture(
            container: container,
            context: container.mainContext,
            app: AppModel(defaults: defaults),
            suite: suite
        )
    }

    private func inputs(
        _ fixture: Fixture,
        clients: [Client],
        headings: [Heading] = [],
        isSearching: Bool = false,
        searchQuery: String = ""
    ) -> LedgerSnapshotCache.Inputs {
        LedgerSnapshotCache.Inputs(
            context: fixture.context,
            clients: clients,
            headings: headings,
            app: fixture.app,
            isSearching: isSearching,
            rowBuilder: LedgerRowBuilder(
                clients: clients,
                headings: headings,
                app: fixture.app,
                composerRoute: nil,
                searchQuery: searchQuery,
                searchTokens: []
            )
        )
    }

    /// `monthsAgo(n)` dated, so a test can place a row inside or outside the
    /// cache's trailing window.
    private func monthsAgo(_ count: Int) -> Date {
        Calendar.current.date(
            byAdding: .month,
            value: -count,
            to: DateFormat.monthStart(of: .now)
        )!
    }

    /// The cache defers its SwiftData work into a yielded task on purpose, so it
    /// never runs inside a scroll callback. A fixed number of `Task.yield()`s is
    /// not a barrier for that — poll the observable result instead, bounded so a
    /// genuine failure still fails rather than hangs.
    private func settle(untilTrue condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test func searchUsesTheFullLedgerSnapshotWhileTheVisibleLedgerStaysCached() throws {
        let fixture = try makeFixture()
        defer { UserDefaults().removePersistentDomain(forName: fixture.suite) }
        let client = Client(name: "Acme")
        let entry = Entry(amount: 240, project: "Mobile", task: "Mobile redesign")
        entry.client = client
        fixture.context.insert(client)
        fixture.context.insert(entry)
        try fixture.context.save()

        let cache = LedgerSnapshotCache()
        let inputs = inputs(fixture, clients: [client], searchQuery: "mobile")

        cache.refreshLedgerSnapshot(inputs)
        #expect(cache.ledgerSnapshot?.hasEntries == true)
        #expect(cache.searchSnapshot == nil)

        cache.beginSearch(inputs)
        #expect(cache.searchSnapshot?.hasEntries == true)
        #expect(cache.searchStats.hitCount == 1)
        #expect(cache.searchStats.earnedTotal == 240)
        #expect(cache.searchFilterSource?.clients.map(\.name) == ["Acme"])

        cache.endSearch()
        #expect(cache.searchSnapshot == nil)
        #expect(cache.searchFilterSource == nil)
        #expect(cache.searchStats.hitCount == 0)
    }

    /// The visible ledger materializes a trailing window; anything older is
    /// reported through `hasOlderMonths` rather than fetched.
    @Test func theInitialWindowExcludesOlderMonthsButReportsThem() throws {
        let fixture = try makeFixture()
        defer { UserDefaults().removePersistentDomain(forName: fixture.suite) }
        let client = Client(name: "Acme")
        let recent = Entry(amount: 100, task: "recent", date: .now)
        let ancient = Entry(amount: 40, task: "ancient", date: monthsAgo(24))
        recent.client = client
        ancient.client = client
        fixture.context.insert(client)
        fixture.context.insert(recent)
        fixture.context.insert(ancient)
        try fixture.context.save()

        let cache = LedgerSnapshotCache()
        cache.refreshLedgerSnapshot(inputs(fixture, clients: [client]))

        let snapshot = try #require(cache.ledgerSnapshot)
        #expect(snapshot.hasOlderMonths)
        #expect(snapshot.hasEntries)
        // The 24-month-old row is outside the eight-month window.
        #expect(!snapshot.months.contains(monthsAgo(24)))
        #expect(snapshot.monthTotal(monthKey: snapshot.key(for: monthsAgo(24))) == 0)
    }

    /// Reaching the window edge extends it by a year, which is what makes the
    /// older month appear. The work is deferred out of the scroll callback, so
    /// the test awaits the yielded task.
    @Test func extendingTheWindowMaterializesAnOlderMonth() async throws {
        let fixture = try makeFixture()
        defer { UserDefaults().removePersistentDomain(forName: fixture.suite) }
        let client = Client(name: "Acme")
        let recent = Entry(amount: 100, task: "recent", date: .now)
        // Inside the first extension (8 + 12 months), outside the initial window.
        let older = Entry(amount: 40, task: "older", date: monthsAgo(10))
        recent.client = client
        older.client = client
        fixture.context.insert(client)
        fixture.context.insert(recent)
        fixture.context.insert(older)
        try fixture.context.save()

        let cache = LedgerSnapshotCache()
        let inputs = inputs(fixture, clients: [client])
        cache.refreshLedgerSnapshot(inputs)
        #expect(cache.ledgerSnapshot?.hasOlderMonths == true)
        #expect(cache.ledgerSnapshot?.monthTotal(
            monthKey: Insights.monthKey(of: monthsAgo(10))
        ) == 0)

        let windowStartBefore = cache.windowStart
        cache.requestWindowExtension(inputs)
        await settle { cache.windowStart < windowStartBefore }

        let snapshot = try #require(cache.ledgerSnapshot)
        #expect(snapshot.months.contains(monthsAgo(10)))
        #expect(snapshot.monthTotal(monthKey: snapshot.key(for: monthsAgo(10))) == 40)
        #expect(!snapshot.hasOlderMonths)
    }

    /// A sync pass saves several times. The refresh coalesces the burst into one
    /// aggregation instead of re-running per save.
    @Test func aBurstOfScheduledRefreshesCoalescesIntoOnePass() async throws {
        let fixture = try makeFixture()
        defer { UserDefaults().removePersistentDomain(forName: fixture.suite) }
        let client = Client(name: "Acme")
        fixture.context.insert(client)
        try fixture.context.save()

        let cache = LedgerSnapshotCache()
        let burstInputs = inputs(fixture, clients: [client])
        #expect(cache.ledgerSnapshot == nil)

        // Three saves in quick succession, as one pull produces.
        cache.scheduleSnapshotRefresh(burstInputs)
        cache.scheduleSnapshotRefresh(burstInputs)
        cache.scheduleSnapshotRefresh(burstInputs)
        await settle { cache.ledgerSnapshot != nil }
        #expect(cache.ledgerSnapshot != nil)

        // The coalescing handle was released, so a later save still schedules
        // its own pass rather than being swallowed by the finished one.
        let client2 = Client(name: "Beta")
        let entry = Entry(amount: 75, task: "later", date: .now)
        entry.client = client2
        fixture.context.insert(client2)
        fixture.context.insert(entry)
        try fixture.context.save()
        cache.scheduleSnapshotRefresh(inputs(fixture, clients: [client, client2]))
        await settle { cache.ledgerSnapshot?.hasEntries == true }
        #expect(cache.ledgerSnapshot?.hasEntries == true)
    }

    /// Scrolling the summary toward the window edge prefetches; a month well
    /// inside the window does not.
    @Test func prefetchOnlyExtendsNearTheWindowEdge() async throws {
        let fixture = try makeFixture()
        defer { UserDefaults().removePersistentDomain(forName: fixture.suite) }
        let client = Client(name: "Acme")
        let recent = Entry(amount: 100, task: "recent", date: .now)
        let older = Entry(amount: 40, task: "older", date: monthsAgo(10))
        recent.client = client
        older.client = client
        fixture.context.insert(client)
        fixture.context.insert(recent)
        fixture.context.insert(older)
        try fixture.context.save()

        let cache = LedgerSnapshotCache()
        let inputs = inputs(fixture, clients: [client])
        cache.refreshLedgerSnapshot(inputs)
        let windowStartBefore = cache.windowStart

        // The trigger is the six-month summary trend reaching past the window:
        // `displayedMonth - 5 months < windowStart`. The window is eight months,
        // so it starts at `thisMonth - 7`.
        //
        // This month: the trend reaches back to `thisMonth - 5`, comfortably
        // inside the window — no prefetch.
        cache.prefetchWindowIfNeeded(for: DateFormat.monthStart(of: .now), inputs: inputs)
        // Nothing should happen, so there is no state to poll for: give the
        // scheduler room and assert the window is untouched.
        await Task.yield()
        await Task.yield()
        #expect(cache.windowStart == windowStartBefore)

        // Three months back: the trend reaches `thisMonth - 8`, one month past
        // the edge, so the next chunk is fetched before the trend can show a gap.
        cache.prefetchWindowIfNeeded(for: monthsAgo(3), inputs: inputs)
        await settle { cache.windowStart < windowStartBefore }
        #expect(cache.windowStart < windowStartBefore)
    }
}
