import Foundation
import SwiftData
import Testing
@testable import earnline

@MainActor
struct LedgerSafetySnapshotTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: EarnlineSchemaV3.self)
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Each test gets its own Application Support root so snapshots written
    /// here never touch the simulator's real folder or each other.
    private func makeApp(storeSuffix: String = UUID().uuidString) -> AppModel {
        let suite = "earnline-safety-snapshot-tests-\(storeSuffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let app = AppModel(defaults: defaults)
        app.workspaceStoreIdentity = "test:\(storeSuffix):account"
        return app
    }

    private func seedLedger(_ context: ModelContext, lines: Int = 3) throws {
        let client = Client(name: "Acme")
        context.insert(client)
        for index in 0..<lines {
            let entry = Entry(amount: Decimal(100 + index), task: "Line \(index)")
            entry.client = client
            context.insert(entry)
        }
        try context.save()
    }

    private func cleanUp(_ app: AppModel) throws {
        for snapshot in try LedgerSafetySnapshots.list(forStoreIdentity: app.workspaceStoreIdentity) {
            try LedgerSafetySnapshots.delete(snapshot)
        }
    }

    @Test func captureWritesARestorableCopyAndAnEmptyStoreWritesNothing() throws {
        let app = makeApp()
        let container = try makeContainer()
        defer { try? cleanUp(app) }

        #expect(try LedgerSafetySnapshots.capture(context: container.mainContext, app: app, reason: .useCloudCopy) == nil)
        #expect(try LedgerSafetySnapshots.list(forStoreIdentity: app.workspaceStoreIdentity).isEmpty)

        try seedLedger(container.mainContext)
        let snapshot = try #require(
            try LedgerSafetySnapshots.capture(context: container.mainContext, app: app, reason: .useCloudCopy)
        )
        #expect(snapshot.reason == .useCloudCopy)
        #expect(snapshot.fileSize > 0)

        let listed = try LedgerSafetySnapshots.list(forStoreIdentity: app.workspaceStoreIdentity)
        #expect(listed.count == 1)
        #expect(listed.first?.url == snapshot.url)

        // Restoring into an emptied store brings every record back as dirty.
        try AppModel.clearLocalStore(container.mainContext)
        let backup = try LedgerSafetySnapshots.load(snapshot)
        let plan = try LedgerBackupCodec.importPlan(backup, into: container.mainContext)
        #expect(plan.inserted == 4)
        #expect(plan.skippedExisting == 0)
        let summary = try LedgerBackupCodec.importBackup(backup, into: container.mainContext)
        try container.mainContext.save()
        #expect(summary.inserted == 4)
        #expect(try container.mainContext.fetch(FetchDescriptor<Entry>()).count == 3)
        #expect(try container.mainContext.fetch(FetchDescriptor<Entry>()).allSatisfy(\.needsSync))
    }

    @Test func onlyTheNewestSnapshotsAreKept() throws {
        let app = makeApp()
        let container = try makeContainer()
        defer { try? cleanUp(app) }
        try seedLedger(container.mainContext, lines: 1)

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for offset in 0..<(LedgerSafetySnapshots.retainedCount + 2) {
            _ = try LedgerSafetySnapshots.capture(
                context: container.mainContext, app: app, reason: .resetAndPull,
                now: base.addingTimeInterval(Double(offset) * 60)
            )
        }

        let listed = try LedgerSafetySnapshots.list(forStoreIdentity: app.workspaceStoreIdentity)
        #expect(listed.count == LedgerSafetySnapshots.retainedCount)
        #expect(listed.first?.createdAt == base.addingTimeInterval(Double(LedgerSafetySnapshots.retainedCount + 1) * 60))
        #expect(listed.last?.createdAt == base.addingTimeInterval(120))
    }

    @Test func snapshotsAreScopedToTheirStore() throws {
        let first = makeApp()
        let second = makeApp()
        let container = try makeContainer()
        defer {
            try? cleanUp(first)
            try? cleanUp(second)
        }
        try seedLedger(container.mainContext, lines: 1)
        _ = try LedgerSafetySnapshots.capture(context: container.mainContext, app: first, reason: .resetAndPull)

        #expect(try LedgerSafetySnapshots.list(forStoreIdentity: first.workspaceStoreIdentity).count == 1)
        #expect(try LedgerSafetySnapshots.list(forStoreIdentity: second.workspaceStoreIdentity).isEmpty)
    }

    @Test func fileNamesRoundTripTheirStampAndReason() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let name = LedgerSafetySnapshots.fileName(for: .useCloudCopy, at: date)
        let parsed = LedgerSafetySnapshots.parseFileName(name)
        #expect(parsed?.reason == .useCloudCopy)
        #expect(parsed?.createdAt == date)
        #expect(LedgerSafetySnapshots.parseFileName("notes.json") == nil)
        #expect(LedgerSafetySnapshots.safeDirectoryName("production:legacy-cache:legacy") == "production-legacy-cache-legacy")
    }

    @Test func importPlanMatchesWhatImportInserts() throws {
        let source = try makeContainer()
        try seedLedger(source.mainContext, lines: 2)
        let backup = try LedgerBackupCodec.decode(
            LedgerBackupCodec.export(context: source.mainContext, app: makeApp())
        )

        let destination = try makeContainer()
        let firstPlan = try LedgerBackupCodec.importPlan(backup, into: destination.mainContext)
        let firstImport = try LedgerBackupCodec.importBackup(backup, into: destination.mainContext)
        try destination.mainContext.save()
        #expect(firstPlan == firstImport)
        #expect(firstPlan.inserted == 3)

        let secondPlan = try LedgerBackupCodec.importPlan(backup, into: destination.mainContext)
        #expect(secondPlan.inserted == 0)
        #expect(secondPlan.skippedExisting == 3)
        // The plan must not have touched the store.
        #expect(destination.mainContext.hasChanges == false)
    }
}
