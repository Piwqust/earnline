import SwiftData
import Testing
@testable import earnline

@MainActor
struct LedgerMutationStoreTests {
    /// Keep the container alive for the whole test. SwiftData contexts do not
    /// retain their container and can otherwise fail after a model mutation.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Client.self, Entry.self, SyncTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func saveAdvancesTheRevisionAndQueuesOneSync() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = LedgerMutationStore()
        var scheduledCount = 0
        store.configureSyncScheduler { _ in scheduledCount += 1 }

        context.insert(Client(name: "Acme"))

        #expect(store.save(context) == nil)
        #expect(store.dataRevision == 1)
        #expect(scheduledCount == 1)
    }

    @Test func deletingThenUndoingAnEntryKeepsTheTombstoneContract() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = LedgerMutationStore()
        var scheduledCount = 0
        store.configureSyncScheduler { _ in scheduledCount += 1 }

        let client = Client(name: "Acme")
        let entry = Entry(amount: 240, project: "App", task: "2 screens")
        entry.client = client
        context.insert(client)
        context.insert(entry)
        try context.save()
        let entryID = entry.id

        #expect(store.delete(entry, context: context) == nil)
        #expect(store.undoableDelete != nil)
        #expect(store.dataRevision == 1)
        #expect(scheduledCount == 1)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).map(\.recordID) == [entryID])

        #expect(store.performUndo(context: context) == nil)
        #expect(store.undoableDelete == nil)
        #expect(store.dataRevision == 2)
        #expect(scheduledCount == 2)
        #expect(try context.fetch(FetchDescriptor<Entry>()).map(\.id) == [entryID])
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    /// The store outlives every workspace switch, so a snapshot captured from
    /// the outgoing container must not stay replayable. Restoring it against the
    /// incoming store would insert the row — and, for a client, every entry it
    /// owned — into the wrong account.
    @Test func discardingTheStagedUndoStopsAReplayIntoAnotherStore() throws {
        let outgoing = try makeContainer()
        let incoming = try makeContainer()
        let store = LedgerMutationStore()
        var scheduledCount = 0
        store.configureSyncScheduler { _ in scheduledCount += 1 }

        let client = Client(name: "Acme")
        let entry = Entry(amount: 240, project: "App", task: "2 screens")
        entry.client = client
        outgoing.mainContext.insert(client)
        outgoing.mainContext.insert(entry)
        try outgoing.mainContext.save()

        #expect(store.delete(entry, context: outgoing.mainContext) == nil)
        #expect(store.undoableDelete != nil)

        store.discardStagedUndo()
        #expect(store.undoableDelete == nil)

        // Nothing staged means nothing to replay: the second store stays empty
        // and no sync is scheduled against it.
        #expect(store.performUndo(context: incoming.mainContext) == nil)
        #expect(try incoming.mainContext.fetch(FetchDescriptor<Entry>()).isEmpty)
        #expect(try incoming.mainContext.fetch(FetchDescriptor<Client>()).isEmpty)
        #expect(scheduledCount == 1)
    }

    /// A restore whose owning client is gone used to save cleanly and report
    /// success, so the toast dismissed and nothing came back.
    @Test func restoringAnEntryWithoutItsClientReportsTheFailure() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = LedgerMutationStore()
        store.configureSyncScheduler { _ in }

        let client = Client(name: "Acme")
        let entry = Entry(amount: 240, project: "App", task: "2 screens")
        entry.client = client
        context.insert(client)
        context.insert(entry)
        try context.save()

        #expect(store.delete(entry, context: context) == nil)
        // The client goes too — as a remote cascade delete would take it.
        context.delete(client)
        try context.save()

        let message = store.performUndo(context: context)
        #expect(message == UndoRestoreError.ownerMissing.localizedDescription)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
        // The rollback leaves the queued delete intact rather than half-applying
        // the failed restore.
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty == false)
    }
}
