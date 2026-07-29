import Foundation
import SwiftData
import Testing
@testable import earnline

@MainActor
struct GuestLedgerMigrationTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: EarnlineSchemaV3.self)
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func guestStoreNameMatchesWorkspaceStoreConvention() {
        // Locks the reconstructed guest file name to what WorkspaceStore builds
        // for the fixed guest key (production · local-guest · account).
        #expect(GuestLedgerMigration.guestStoreName == "earnline-production-local-guest")
    }

    @Test func copiesGuestLedgerIntoAccountStoreMarkedDirty() throws {
        let source = ModelContext(try makeContainer())
        let destination = ModelContext(try makeContainer())

        // A guest ledger is fully "synced" only to its own local file; it has
        // never reached a real workspace.
        let client = Client(name: "Acme", syncState: .synced, lastSyncedAt: .now)
        source.insert(client)
        let entry = Entry(amount: 240, currencyCode: "USD", project: "Kit", task: "Screens",
                          status: .paid, syncState: .synced, lastSyncedAt: .now)
        entry.client = client
        source.insert(entry)
        source.insert(Heading(title: "April", date: .now, syncState: .synced, lastSyncedAt: .now))
        try source.save()

        let summary = try GuestLedgerMigration.importLedger(from: source, into: destination)

        #expect(summary.clients == 1)
        #expect(summary.entries == 1)
        #expect(summary.headings == 1)
        #expect(summary.monthReviews == 0)
        #expect(summary.total == 3)

        let copiedEntries = try destination.fetch(FetchDescriptor<Entry>())
        #expect(copiedEntries.count == 1)
        let copied = try #require(copiedEntries.first)
        #expect(copied.id == entry.id)                 // identity preserved
        #expect(copied.amount == 240)
        #expect(copied.needsSync)                      // dirty → next sync pushes it
        #expect(copied.lastSyncedAt == nil)            // no server baseline yet
        #expect(copied.client?.id == client.id)        // re-linked to its owner

        let copiedClient = try #require(try destination.fetch(FetchDescriptor<Client>()).first)
        #expect(copiedClient.needsSync)

        // The guest store is only read — never mutated.
        #expect(try source.fetch(FetchDescriptor<Entry>()).count == 1)
    }

    @Test func importIsIdempotent() throws {
        let source = ModelContext(try makeContainer())
        let destination = ModelContext(try makeContainer())

        let client = Client(name: "Acme")
        source.insert(client)
        let entry = Entry(amount: 100, task: "One")
        entry.client = client
        source.insert(entry)
        try source.save()

        let first = try GuestLedgerMigration.importLedger(from: source, into: destination)
        #expect(first.total == 2)

        // Running again copies nothing and leaves the destination unchanged.
        let second = try GuestLedgerMigration.importLedger(from: source, into: destination)
        #expect(second.total == 0)
        #expect(try destination.fetch(FetchDescriptor<Entry>()).count == 1)
        #expect(try destination.fetch(FetchDescriptor<Client>()).count == 1)
    }

    @Test func neverOverwritesAnAccountRowWithTheSameID() throws {
        let source = ModelContext(try makeContainer())
        let destination = ModelContext(try makeContainer())

        let sharedID = UUID()
        source.insert(Client(id: sharedID, name: "Guest name"))
        try source.save()

        // The account already has a row with the same id but its own value.
        destination.insert(Client(id: sharedID, name: "Account name", syncState: .synced))
        try destination.save()

        let summary = try GuestLedgerMigration.importLedger(from: source, into: destination)
        #expect(summary.clients == 0)

        let clients = try destination.fetch(FetchDescriptor<Client>())
        #expect(clients.count == 1)
        #expect(clients.first?.name == "Account name")   // account copy wins
    }

    @Test func skipsDuplicateProjectIconByKey() throws {
        let source = ModelContext(try makeContainer())
        let destination = ModelContext(try makeContainer())

        let key = ProjectIconResolver.normalizedKey(for: "Launch Kit")
        let guestID = try #require(ProjectIconResolver.preferenceID(for: "Launch Kit"))
        source.insert(ProjectIconPreference(id: guestID, projectKey: key, symbol: .display))
        try source.save()

        // Account already has an icon for the same project key (unique column).
        destination.insert(ProjectIconPreference(id: guestID, projectKey: key, symbol: .camera,
                                                 syncState: .synced))
        try destination.save()

        let summary = try GuestLedgerMigration.importLedger(from: source, into: destination)
        #expect(summary.projectIcons == 0)
        #expect(try destination.fetch(FetchDescriptor<ProjectIconPreference>()).count == 1)
    }

    @Test func copiesMonthReviewIntoAccountStoreMarkedDirty() throws {
        let source = ModelContext(try makeContainer())
        let destination = ModelContext(try makeContainer())
        let monthStart = try #require(SyncDateCodec.parseDay("2026-07-01"))
        let closedAt = try #require(SyncDateCodec.parseTimestamp("2026-07-21T09:30:00.000Z"))
        let review = MonthReview(monthStart: monthStart,
                                 note: "Closed after delivery",
                                 closedAt: closedAt,
                                 syncState: .synced,
                                 lastSyncedAt: closedAt)
        source.insert(review)
        try source.save()

        let summary = try GuestLedgerMigration.importLedger(from: source, into: destination)

        #expect(summary.monthReviews == 1)
        #expect(summary.total == 1)
        let copied = try #require(try destination.fetch(FetchDescriptor<MonthReview>()).first)
        #expect(copied.id == review.id)
        #expect(copied.note == "Closed after delivery")
        #expect(copied.closedAt == closedAt)
        #expect(copied.needsSync)
        #expect(copied.lastSyncedAt == nil)
    }
}
