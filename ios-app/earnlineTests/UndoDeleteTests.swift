import Foundation
import SwiftData
import Testing
@testable import earnline

@MainActor
struct UndoDeleteTests {
    /// The container must stay alive for the test's duration — a context
    /// whose container deallocates traps inside SwiftData on first use.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Client.self, Entry.self, Heading.self, SyncTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func entryRestoreRoundTripsAndDropsTombstone() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let client = Client(name: "Acme")
        let entry = Entry(amount: 240,
                          project: "App",
                          task: "2 screens",
                          holdUntil: Date(timeIntervalSinceNow: 86_400),
                          status: .inProgress,
                          syncState: .synced)
        entry.client = client
        context.insert(client)
        context.insert(entry)
        try context.save()
        let snapshot = UndoableDelete.entry(EntrySnapshot(entry))
        let entryID = entry.id

        SyncDeleteQueue.enqueue(.entry, id: entryID, in: context)
        context.delete(entry)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).count == 1)

        try snapshot.restore(in: context)
        try context.save()

        let restored = try #require(try context.fetch(FetchDescriptor<Entry>()).first)
        #expect(restored.id == entryID)
        #expect(restored.amount == 240)
        #expect(restored.project == "App")
        #expect(restored.status == .inProgress)
        #expect(restored.holdUntil != nil)
        #expect(restored.client?.name == "Acme")
        // Dirty with a fresh edit stamp, so the next pass re-pushes it and a
        // tombstone that already reached the server can't re-kill it.
        #expect(restored.syncState == .dirty)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test func clientRestoreRecreatesItsEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let client = Client(name: "Studio X", colorHex: "#7B00FF", sortIndex: 3)
        let a = Entry(amount: 100, task: "logo")
        let b = Entry(amount: 200, task: "site", status: .inProgress)
        a.client = client
        b.client = client
        context.insert(client)
        try context.save()
        let snapshot = UndoableDelete.client(ClientSnapshot(client))
        let clientID = client.id

        SyncDeleteQueue.enqueue(.client, id: clientID, in: context)
        context.delete(client) // cascades to entries
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)

        try snapshot.restore(in: context)
        try context.save()

        let restored = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(restored.id == clientID)
        #expect(restored.colorHex == "#7B00FF")
        #expect(restored.sortIndex == 3)
        #expect(restored.syncState == .dirty)
        #expect(restored.entries.count == 2)
        #expect(restored.entries.allSatisfy { $0.syncState == .dirty })
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test func headingRestoreRoundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let heading = Heading(title: "Retainers", sortIndex: 2)
        context.insert(heading)
        try context.save()
        let snapshot = UndoableDelete.heading(HeadingSnapshot(heading))
        let headingID = heading.id

        SyncDeleteQueue.enqueue(.heading, id: headingID, in: context)
        context.delete(heading)
        try context.save()

        try snapshot.restore(in: context)
        try context.save()

        let restored = try #require(try context.fetch(FetchDescriptor<Heading>()).first)
        #expect(restored.id == headingID)
        #expect(restored.title == "Retainers")
        #expect(restored.syncState == .dirty)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test func entryRestoreWithoutOwnerIsDroppedSafely() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let client = Client(name: "Gone")
        let entry = Entry(amount: 50, task: "x")
        entry.client = client
        context.insert(client)
        try context.save()
        let snapshot = UndoableDelete.entry(EntrySnapshot(entry))

        // The whole client vanishes (e.g. deleted on another device) after
        // the entry delete was staged.
        context.delete(client)
        try context.save()

        try snapshot.restore(in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
    }
}
