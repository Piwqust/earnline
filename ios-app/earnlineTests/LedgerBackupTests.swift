import Foundation
import SwiftData
import Testing
@testable import earnline

@MainActor
struct LedgerBackupTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: EarnlineSchemaV3.self)
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeApp() -> AppModel {
        let suite = "earnline-backup-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(defaults: defaults)
    }

    @Test func roundTripsAllUserFacingWorkspaceRecords() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let client = Client(name: "Acme", colorHex: "#0088FF", sortIndex: 2)
        let entry = Entry(amount: 240.50, currencyCode: "USD", project: "Launch",
                          task: "Screens", date: .now, holdUntil: .now.addingTimeInterval(86_400),
                          status: .inProgress, sortIndex: 1)
        entry.client = client
        sourceContext.insert(client)
        sourceContext.insert(entry)
        sourceContext.insert(Heading(title: "Delivery", date: .now))
        sourceContext.insert(ProjectIconPreference(id: try #require(ProjectIconResolver.preferenceID(for: "Launch")),
                                                   projectKey: "launch", symbol: .display))
        sourceContext.insert(MonthReview(monthStart: .now, note: "Closed after delivery", closedAt: .now))
        try sourceContext.save()

        let data = try LedgerBackupCodec.export(context: sourceContext, app: makeApp())
        let backup = try LedgerBackupCodec.decode(data)

        #expect(backup.formatVersion == LedgerBackup.currentVersion)
        #expect(backup.clients.count == 1)
        #expect(backup.entries.count == 1)
        #expect(backup.headings.count == 1)
        #expect(backup.projectIcons.count == 1)
        #expect(backup.monthReviews.count == 1)
        #expect(backup.entries.first?.amount == "240.5")

        let destination = try makeContainer()
        let summary = try LedgerBackupCodec.importBackup(backup, into: destination.mainContext)
        try destination.mainContext.save()

        #expect(summary.inserted == 5)
        #expect(summary.skippedExisting == 0)
        #expect(try destination.mainContext.fetch(FetchDescriptor<Client>()).count == 1)
        #expect(try destination.mainContext.fetch(FetchDescriptor<Entry>()).first?.client?.name == "Acme")
        #expect(try destination.mainContext.fetch(FetchDescriptor<MonthReview>()).first?.note == "Closed after delivery")
        #expect(try destination.mainContext.fetch(FetchDescriptor<Entry>()).first?.needsSync == true)
    }

    @Test func importingTheSameBackupAgainDoesNotDuplicateRecords() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let client = Client(name: "Acme")
        sourceContext.insert(client)
        let entry = Entry(amount: 100, task: "One")
        entry.client = client
        sourceContext.insert(entry)
        try sourceContext.save()

        let backup = try LedgerBackupCodec.decode(
            LedgerBackupCodec.export(context: sourceContext, app: makeApp())
        )
        let destination = try makeContainer()
        let first = try LedgerBackupCodec.importBackup(backup, into: destination.mainContext)
        try destination.mainContext.save()
        let second = try LedgerBackupCodec.importBackup(backup, into: destination.mainContext)

        #expect(first.inserted == 2)
        #expect(second.inserted == 0)
        #expect(second.skippedExisting == 2)
        #expect(try destination.mainContext.fetch(FetchDescriptor<Entry>()).count == 1)
    }

    @Test func importRejectsAMonthReviewWhoseIdDoesNotMatchTheMonth() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let wrongID = UUID()
        let backup = LedgerBackup(
            formatVersion: LedgerBackup.currentVersion,
            exportedAt: date,
            workspaceID: "backup-test-workspace",
            settings: .init(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", exchangeRate: "90"),
            clients: [],
            entries: [],
            headings: [],
            projectIcons: [],
            monthReviews: [
                .init(id: wrongID, monthStart: date, note: "Closed", closedAt: date,
                      createdAt: date, updatedAt: date)
            ]
        )

        #expect(throws: LedgerBackupError.invalidMonthReview(wrongID)) {
            try backup.validated()
        }
    }

    @Test func exportRejectsAnOrphanedIncomeLine() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Entry(amount: 100, task: "Orphan"))
        try context.save()
        let orphanID = try #require(try context.fetch(FetchDescriptor<Entry>()).first?.id)

        #expect(throws: LedgerBackupError.orphanedEntry(orphanID)) {
            try LedgerBackupCodec.export(context: context, app: makeApp())
        }
    }

    @Test func importPreservesLocalEditsAndReusesTheExistingClient() throws {
        let backup = makeBackup()
        let clientID = try #require(backup.clients.first?.id)
        let entryID = try #require(backup.entries.first?.id)
        let container = try makeContainer()
        let context = container.mainContext
        let client = Client(id: clientID, name: "Locally renamed client")
        let entry = Entry(id: entryID, amount: 999, task: "Locally edited task")
        context.insert(client)
        context.insert(entry)
        entry.client = client
        try context.save()

        let repeated = try LedgerBackupCodec.importBackup(backup, into: context)
        #expect(repeated.inserted == 0)
        #expect(repeated.skippedExisting == 2)
        #expect(!context.hasChanges)

        let additional = makeBackup(clientID: clientID)
        let newEntryID = try #require(additional.entries.first?.id)
        let added = try LedgerBackupCodec.importBackup(additional, into: context)
        try context.save()

        #expect(added.clients == 0)
        #expect(added.entries == 1)
        #expect(added.skippedExisting == 1)
        let clients = try context.fetch(FetchDescriptor<Client>())
        #expect(clients.count == 1)
        #expect(clients.first?.name == "Locally renamed client")
        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 2)
        let preserved = try #require(entries.first { $0.id == entryID })
        #expect(preserved.amount == 999)
        #expect(preserved.task == "Locally edited task")
        #expect(entries.first { $0.id == newEntryID }?.client?.id == clientID)
        #expect(Set(client.entries.map(\.id)) == [entryID, newEntryID])
    }

    @Test(arguments: ["0", "-1", "not-a-number"])
    func invalidBackupDoesNotPartiallyChangeTheLedger(amount: String) throws {
        let backup = makeBackup(amount: amount)
        let entryID = try #require(backup.entries.first?.id)
        let container = try makeContainer()
        let context = container.mainContext
        let existingClient = Client(name: "Existing client")
        context.insert(existingClient)
        try context.save()

        #expect(throws: LedgerBackupError.invalidAmount(entryID)) {
            try LedgerBackupCodec.importBackup(backup, into: context)
        }

        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<Client>()).map(\.id) == [existingClient.id])
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test(arguments: [("USD", "0.01"), ("EUR", "240.5"), ("RUB", "999999999.99")])
    func importedBackupSurvivesReopeningTheDiskStore(currency: String, amount: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "earnline-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record(error, "Could not remove the isolated backup test store")
            }
        }
        let storeURL = directory.appending(path: "backup.store")
        let schema = Schema(versionedSchema: EarnlineSchemaV3.self)
        let configuration = ModelConfiguration("BackupPersistence", schema: schema, url: storeURL,
                                               cloudKitDatabase: .none)
        let backup = makeBackup(amount: amount, currencyCode: currency)
        let clientID = try #require(backup.clients.first?.id)
        let entryID = try #require(backup.entries.first?.id)

        do {
            let container = try ModelContainer(for: schema, migrationPlan: EarnlineMigrationPlan.self,
                                               configurations: configuration)
            let summary = try LedgerBackupCodec.importBackup(backup, into: container.mainContext)
            #expect(summary.inserted == 2)
            let mutations = LedgerMutationStore()
            try #require(mutations.save(container.mainContext) == nil)
        }

        #expect(FileManager.default.fileExists(atPath: storeURL.path))
        let reopened = try ModelContainer(for: schema, migrationPlan: EarnlineMigrationPlan.self,
                                          configurations: configuration)
        let entries = try reopened.mainContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.id == entryID)
        #expect(entry.client?.id == clientID)
        #expect(NSDecimalNumber(decimal: entry.amount).stringValue == amount)
        #expect(entry.currencyCode == currency)
        #expect(entry.task == "Backup task")
        #expect(entry.status == .inProgress)
        #expect(entry.needsSync)
        let client = try #require(try reopened.mainContext.fetch(FetchDescriptor<Client>()).first)
        #expect(client.entries.map(\.id) == [entryID])
        #expect(try reopened.mainContext.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)

        let repeated = try LedgerBackupCodec.importBackup(backup, into: reopened.mainContext)
        #expect(repeated.inserted == 0)
        #expect(repeated.skippedExisting == 2)
        #expect(!reopened.mainContext.hasChanges)
    }

    private func makeBackup(clientID: UUID = UUID(), amount: String = "240.5",
                            currencyCode: String = "USD") -> LedgerBackup {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return LedgerBackup(
            formatVersion: LedgerBackup.currentVersion,
            exportedAt: date,
            workspaceID: "backup-test-workspace",
            settings: .init(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", exchangeRate: "90"),
            clients: [.init(id: clientID, name: "Backup client", colorHex: "#0088FF",
                             sortIndex: 0, createdAt: date, updatedAt: date)],
            entries: [.init(id: UUID(), clientID: clientID, amount: amount, currencyCode: currencyCode,
                             project: "Backup project", task: "Backup task", date: date, holdUntil: nil,
                             status: .inProgress, sortIndex: 0, createdAt: date, updatedAt: date)],
            headings: [], projectIcons: [], monthReviews: []
        )
    }
}
