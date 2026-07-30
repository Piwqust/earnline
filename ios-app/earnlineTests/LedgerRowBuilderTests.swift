import Foundation
import SwiftData
import Testing
@testable import earnline

/// `LedgerRowBuilder` turns one cached aggregation snapshot into the ordered row
/// model the ledger list renders. It had no direct coverage, so the row order —
/// dated event notes before client groups, entries under their client, the
/// composer wedged between a client and its rows — was only ever asserted
/// through the UI tests.
///
/// Every fixture is inserted into a real in-memory container: the builder skips
/// rows failing `isInvalidated`, which is true for a free-standing model (it has
/// no `modelContext`). That is the same guard production relies on to survive a
/// sync pull deleting a row mid-render.
@MainActor
struct LedgerRowBuilderTests {
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let app: AppModel
    }

    private func makeFixture() throws -> Fixture {
        let suite = "earnline-row-builder-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let container = try ModelContainer(
            for: Client.self, Entry.self, Heading.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Fixture(
            container: container,
            context: container.mainContext,
            app: AppModel(defaults: defaults)
        )
    }

    private var thisMonth: Date { DateFormat.monthStart(of: .now) }

    private func builder(
        _ fixture: Fixture,
        clients: [Client],
        headings: [Heading] = [],
        composerRoute: LedgerComposerRoute? = nil,
        searchQuery: String = "",
        searchTokens: [LedgerSearchToken] = []
    ) -> LedgerRowBuilder {
        LedgerRowBuilder(
            clients: clients,
            headings: headings,
            app: fixture.app,
            composerRoute: composerRoute,
            searchQuery: searchQuery,
            searchTokens: searchTokens
        )
    }

    /// Compact shape of the row model, so assertions read as the list does.
    private func shape(_ rows: [LedgerRow]) -> [String] {
        rows.map { row in
            switch row {
            case .month: "month"
            case .heading(let heading, _): "heading(\(heading.title))"
            case .client(let client, _, let total): "client(\(client.name),\(total))"
            case .composer(let client, _): "composer(\(client.name))"
            case .entry(let entry, _): "entry(\(entry.task))"
            }
        }
    }

    @Test func rowsPlaceEntriesUnderTheirClientWithTheMonthTotalLeading() throws {
        let fixture = try makeFixture()
        let client = Client(name: "Acme")
        let first = Entry(amount: 100, task: "first", date: thisMonth, sortIndex: 0)
        let second = Entry(amount: 50, task: "second", date: thisMonth, sortIndex: 1)
        first.client = client
        second.client = client
        fixture.context.insert(client)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()

        let snapshot = fixture.app.insights.ledgerSnapshot([client])
        let rows = builder(fixture, clients: [client])
            .rows(in: snapshot, isSearching: false, searchSnapshot: nil)

        #expect(shape(rows) == ["month", "client(Acme,150)", "entry(first)", "entry(second)"])
    }

    /// A note is a dated event, not a movable divider: events lead a month, and
    /// income stays in its familiar client groups underneath.
    @Test func datedEventNotesLeadTheMonthAheadOfClientGroups() throws {
        let fixture = try makeFixture()
        let client = Client(name: "Acme")
        let line = Entry(amount: 100, task: "line", date: thisMonth)
        line.client = client
        let note = Heading(title: "Retainer renewed", date: thisMonth)
        fixture.context.insert(client)
        fixture.context.insert(line)
        fixture.context.insert(note)
        try fixture.context.save()

        let snapshot = fixture.app.insights.ledgerSnapshot([client])
        let rows = builder(fixture, clients: [client], headings: [note])
            .rows(in: snapshot, isSearching: false, searchSnapshot: nil)

        #expect(shape(rows) == [
            "month", "heading(Retainer renewed)", "client(Acme,100)", "entry(line)",
        ])
    }

    /// The composer sits between its client's header and that client's rows, and
    /// only in the month it was opened in.
    @Test func theComposerAppearsUnderItsClientInItsOwnMonthOnly() throws {
        let fixture = try makeFixture()
        let client = Client(name: "Acme")
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: thisMonth)!
        let now = Entry(amount: 100, task: "now", date: thisMonth)
        let then = Entry(amount: 40, task: "then", date: lastMonth)
        now.client = client
        then.client = client
        fixture.context.insert(client)
        fixture.context.insert(now)
        fixture.context.insert(then)
        try fixture.context.save()

        let route = LedgerComposerRoute(clientID: client.id, month: thisMonth)
        let snapshot = fixture.app.insights.ledgerSnapshot([client])
        let rowBuilder = builder(fixture, clients: [client], composerRoute: route)
        let rows = rowBuilder.rows(in: snapshot, isSearching: false, searchSnapshot: nil)

        #expect(shape(rows) == [
            "month", "client(Acme,100)", "composer(Acme)", "entry(now)",
            "month", "client(Acme,40)", "entry(then)",
        ])
        #expect(rowBuilder.isComposerMonth(thisMonth))
        #expect(!rowBuilder.isComposerMonth(lastMonth))
        #expect(rowBuilder.activeComposerClient?.id == client.id)
    }

    /// A brand-new client with no lines yet is still content — otherwise
    /// creating your first client dead-ends on the empty state instead of
    /// opening the composer it just promised.
    @Test func anOpenComposerCountsAsContentBeforeTheFirstEntryExists() throws {
        let fixture = try makeFixture()
        let client = Client(name: "Acme")
        fixture.context.insert(client)
        try fixture.context.save()

        let snapshot = fixture.app.insights.ledgerSnapshot([client])
        #expect(!snapshot.hasEntries)
        #expect(!builder(fixture, clients: [client]).hasContent(in: snapshot))

        let withComposer = builder(
            fixture,
            clients: [client],
            composerRoute: LedgerComposerRoute(clientID: client.id, month: thisMonth)
        )
        #expect(withComposer.hasContent(in: snapshot))
        // Its client group is synthesized so the composer has somewhere to live.
        #expect(shape(withComposer.rows(in: snapshot, isSearching: false, searchSnapshot: nil))
            == ["month", "client(Acme,0)", "composer(Acme)"])
    }

    /// Search re-projects the same snapshot: only matching rows survive, and each
    /// month's total is recomputed from the hits rather than the whole month.
    @Test func searchRowsKeepOnlyMatchesAndTotalThem() throws {
        let fixture = try makeFixture()
        let client = Client(name: "Acme")
        let hit = Entry(amount: 100, project: "Mobile", task: "redesign", date: thisMonth, sortIndex: 0)
        let miss = Entry(amount: 900, project: "Print", task: "poster", date: thisMonth, sortIndex: 1)
        hit.client = client
        miss.client = client
        fixture.context.insert(client)
        fixture.context.insert(hit)
        fixture.context.insert(miss)
        try fixture.context.save()

        let snapshot = fixture.app.insights.ledgerSnapshot([client])
        let rowBuilder = builder(fixture, clients: [client], searchQuery: "mobile")
        #expect(rowBuilder.hasSearchFilter)
        #expect(rowBuilder.searchHits.map(\.task) == ["redesign"])

        let rows = rowBuilder.rows(in: snapshot, isSearching: true, searchSnapshot: snapshot)
        // The client total is the matched 100, not the month's 1000.
        #expect(shape(rows) == ["month", "client(Acme,100)", "entry(redesign)"])
    }

    @Test func anInactiveSearchProducesNoRowsAndNoHits() throws {
        let fixture = try makeFixture()
        let client = Client(name: "Acme")
        let line = Entry(amount: 100, task: "line", date: thisMonth)
        line.client = client
        fixture.context.insert(client)
        fixture.context.insert(line)
        try fixture.context.save()

        let snapshot = fixture.app.insights.ledgerSnapshot([client])
        let rowBuilder = builder(fixture, clients: [client])
        #expect(!rowBuilder.hasSearchFilter)
        #expect(rowBuilder.searchHits.isEmpty)
        #expect(rowBuilder.rows(in: snapshot, isSearching: true, searchSnapshot: snapshot).isEmpty)
    }
}
