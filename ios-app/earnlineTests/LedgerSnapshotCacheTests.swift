import Foundation
import SwiftData
import Testing
@testable import earnline

@MainActor
struct LedgerSnapshotCacheTests {
    @Test func searchUsesTheFullLedgerSnapshotWhileTheVisibleLedgerStaysCached() throws {
        let suite = "earnline-snapshot-cache-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let container = try ModelContainer(
            for: Client.self, Entry.self, Heading.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let app = AppModel(defaults: defaults)
        let client = Client(name: "Acme")
        let entry = Entry(amount: 240, project: "Mobile", task: "Mobile redesign")
        entry.client = client
        context.insert(client)
        context.insert(entry)
        try context.save()

        let builder = LedgerRowBuilder(
            clients: [client],
            headings: [],
            app: app,
            composerRoute: nil,
            searchQuery: "mobile",
            searchTokens: []
        )
        let cache = LedgerSnapshotCache()
        let inputs = LedgerSnapshotCache.Inputs(
            context: context,
            clients: [client],
            headings: [],
            app: app,
            isSearching: false,
            rowBuilder: builder
        )

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
}
