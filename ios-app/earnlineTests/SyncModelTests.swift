import Foundation
import SwiftData
import Testing
@testable import earnline

struct SyncModelTests {
    @Test @MainActor func workspaceCurrencyProfilesStaySeparateAndMigrationPullsCloudFirst() {
        let suite = "earnline-workspace-profile-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Legacy builds stored one tuple globally and could leave either
        // workspace marked dirty. The migration keeps an offline Production
        // cache but clears both dirty flags so the cloud wins first.
        defaults.set("EUR", forKey: "baseCurrencyCode")
        defaults.set("GBP", forKey: "secondaryCurrencyCode")
        defaults.set(77.25, forKey: "rate")
        defaults.set(true, forKey: "profileNeedsSync.production")
        defaults.set(true, forKey: "profileNeedsSync.test")

        let app = AppModel(defaults: defaults)

        #expect(app.workspaceEnvironment == .production)
        #expect(app.baseCurrencyCode == "EUR")
        #expect(app.secondaryCurrencyCode == "GBP")
        #expect(app.rate == 77.25)
        #expect(defaults.bool(forKey: "profileNeedsSync.production") == false)
        #expect(defaults.bool(forKey: "profileNeedsSync.test") == false)

        app.rate = 91.5
        #expect(defaults.double(forKey: "rate.production") == 91.5)

        app.workspaceEnvironment = .test
        #expect(app.baseCurrencyCode == AppModel.defaultBaseCurrencyCode)
        #expect(app.secondaryCurrencyCode == AppModel.defaultSecondaryCurrencyCode)
        #expect(app.rate == AppModel.defaultExchangeRate)

        app.rate = 72.0
        #expect(defaults.double(forKey: "rate.test") == 72.0)

        app.workspaceEnvironment = .production
        #expect(app.baseCurrencyCode == "EUR")
        #expect(app.secondaryCurrencyCode == "GBP")
        #expect(app.rate == 91.5)
        #expect(defaults.double(forKey: "rate") == 77.25)
    }

    @Test @MainActor func v1StoreLightweightMigratesToProjectIconSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "earnline-project-icons-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "migration.store")

        do {
            let schema = Schema(versionedSchema: EarnlineSchemaV1.self)
            let configuration = ModelConfiguration("MigrationV1", schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: configuration)
            container.mainContext.insert(Client(name: "Preserved Client"))
            try container.mainContext.save()
        }

        do {
            let schema = Schema(versionedSchema: EarnlineSchemaV2.self)
            let configuration = ModelConfiguration("MigrationV2", schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: EarnlineMigrationPlan.self,
                configurations: configuration
            )
            #expect(try container.mainContext.fetch(FetchDescriptor<Client>()).first?.name == "Preserved Client")
            #expect(try container.mainContext.fetch(FetchDescriptor<ProjectIconPreference>()).isEmpty)
        }
    }

    @Test @MainActor func projectIconPreferenceNormalizesAndUpdatesInPlace() throws {
        let container = try ModelContainer(
            for: ProjectIconPreference.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let preference = try ProjectIconPreferenceStore.set(
            .camera,
            for: "  Café   Site\n",
            in: context
        )
        try context.save()

        #expect(preference.projectKey == "cafe site")
        #expect(preference.id == ProjectIconResolver.preferenceID(for: "CAFE SITE"))
        #expect(preference.symbol == .camera)

        let updated = try ProjectIconPreferenceStore.set(.video, for: "Cafe Site", in: context)
        #expect(updated === preference)
        #expect(updated.symbol == .video)
        #expect(updated.syncState == .dirty)

        updated.symbolNameRaw = "not.a.real.symbol"
        #expect(updated.symbol == .folder)
        #expect(throws: ProjectIconPreferenceError.emptyProjectName) {
            try ProjectIconPreferenceStore.set(.briefcase, for: "  \n", in: context)
        }
    }

    @Test func remoteProjectIconEncodesAllowlistedSymbol() throws {
        let id = try #require(ProjectIconResolver.preferenceID(for: "Launch Kit"))
        let preference = ProjectIconPreference(
            id: id,
            projectKey: ProjectIconResolver.normalizedKey(for: "Launch Kit"),
            symbol: .paintpalette
        )

        let data = try JSONEncoder().encode(RemoteProjectIcon(preference, workspaceID: "test-workspace"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["project_key"] as? String == "launch kit")
        #expect(object["symbol_name"] as? String == "paintpalette")
        #expect(object["workspace_id"] as? String == "test-workspace")
    }

    @Test func workspaceProfileRateEncodesAsDecimalString() throws {
        let payload = WorkspaceProfilePayload(workspaceID: "test-workspace",
                                              baseCurrencyCode: "USD",
                                              secondaryCurrencyCode: "RUB",
                                              exchangeRate: 89.125)
        let data = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["exchange_rate"] as? String == "89.125")
        #expect(object["base_currency_code"] as? String == "USD")
        #expect(object["secondary_currency_code"] as? String == "RUB")
    }

    @Test func remoteEntryEncodesMoneyAsDecimalString() throws {
        let client = Client(name: "Acme Studio")
        let entry = Entry(amount: Decimal(string: "99.50")!,
                          currencyCode: "USD",
                          task: "QA fixes",
                          status: .canceled)
        entry.client = client

        let remote = try #require(RemoteEntry(entry, workspaceID: "test-workspace"))
        let data = try JSONEncoder().encode(remote)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["amount"] as? String == "99.50")
        #expect(object["status"] as? String == "canceled")
    }

    @Test func remoteEntryEncodesLargeGroupedMoneyPrecisely() throws {
        let client = Client(name: "Northstar Labs")
        let entry = Entry(amount: Decimal(string: "123456789.12")!,
                          currencyCode: "USD",
                          task: "Enterprise package",
                          status: .paid)
        entry.client = client

        let remote = try #require(RemoteEntry(entry, workspaceID: "test-workspace"))
        let data = try JSONEncoder().encode(remote)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["amount"] as? String == "123456789.12")
    }

    @Test func legacyLoggedStatusMapsToPaidForSync() throws {
        let client = Client(name: "Acme Studio")
        let entry = Entry(amount: 10, task: "Legacy row", status: .paid)
        entry.statusRaw = "logged"
        entry.client = client

        let remote = try #require(RemoteEntry(entry, workspaceID: "test-workspace"))

        #expect(entry.status == .paid)
        #expect(remote.status == "paid")
    }

    @Test @MainActor func canceledEntriesAreExcludedFromEarnedTotals() {
        let app = AppModel()
        app.baseCurrencyCode = "USD"
        app.secondaryCurrencyCode = "RUB"
        app.rate = 100

        let client = Client(name: "Acme Studio")
        let monthDate = date(year: 2026, month: 6, day: 15)
        let paid = Entry(amount: 100, task: "Paid", date: monthDate, status: .paid, sortIndex: 0)
        let progress = Entry(amount: 50, task: "Progress", date: monthDate, status: .inProgress, sortIndex: 1)
        let canceled = Entry(amount: 25, task: "Canceled", date: monthDate, status: .canceled, sortIndex: 2)

        client.entries = [paid, progress, canceled]

        #expect(app.total(of: client, in: monthDate) == 150)
        #expect(app.monthTotal([client], in: monthDate) == 150)
        #expect(app.entries(of: client, in: monthDate).count == 3)
        #expect(app.earnedEntries(of: client, in: monthDate).count == 2)
    }

    @Test func syncRetryDelaysBackOffThenStop() {
        #expect(AppModel.retryDelay(attempt: 0) == .seconds(5))
        #expect(AppModel.retryDelay(attempt: 1) == .seconds(15))
        #expect(AppModel.retryDelay(attempt: 2) == .seconds(45))
        #expect(AppModel.retryDelay(attempt: 3) == .seconds(120))
        #expect(AppModel.retryDelay(attempt: 4) == nil)
        #expect(AppModel.retryDelay(attempt: -1) == nil)
    }

    @Test func invalidExchangeRatesFallBackToSafeValues() {
        #expect(AppModel.validExchangeRate(0, fallback: 42) == 42)
        #expect(AppModel.validExchangeRate(-1, fallback: 42) == 42)
        #expect(AppModel.validExchangeRate(.nan, fallback: -1) == AppModel.defaultExchangeRate)
        #expect(AppModel.validExchangeRate(.infinity, fallback: 42) == 42)
    }

    @Test @MainActor func identicalCurrenciesAreSeparatedAndSecondaryDisplaysRoundedWholeAmount() {
        let app = AppModel()
        app.baseCurrencyCode = "EUR"
        app.secondaryCurrencyCode = "EUR"

        #expect(app.secondaryCurrencyCode != app.baseCurrencyCode)

        app.baseCurrencyCode = "USD"
        app.secondaryCurrencyCode = "RUB"
        app.rate = 89.125
        #expect(app.secondaryString(Decimal(string: "99.50")!) == "8\u{00A0}868 ₽")
    }

    @Test func dayStringsRoundTripAsCalendarDays() throws {
        let cal = Calendar.current
        // Local midnight — the shape every DatePicker / parsed hold date has.
        let midnight = date(year: 2026, month: 7, day: 4)
        #expect(SyncDateCodec.dayString(midnight) == "2026-07-04")

        let parsed = try #require(SyncDateCodec.parseDay("2026-07-04"))
        let comps = cal.dateComponents([.year, .month, .day], from: parsed)
        #expect(comps.year == 2026)
        #expect(comps.month == 7)
        #expect(comps.day == 4)

        // Late-evening instants still format as their local calendar day.
        let evening = cal.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: 23, minute: 30))!
        #expect(SyncDateCodec.dayString(evening) == "2026-07-04")

        // Malformed wire values must be rejected, not defaulted to today.
        #expect(SyncDateCodec.parseDay("not-a-day") == nil)
        #expect(SyncDateCodec.parseTimestamp("garbage") == nil)
    }

    @Test func syncMoneyDecodesJSONNumbersToTwoDecimalPlaces() throws {
        struct Row: Codable { let amount: SyncMoney }
        // PostgREST sends numeric columns as JSON numbers; the Double detour
        // must not leave binary dust on the decoded Decimal.
        let row = try JSONDecoder().decode(Row.self, from: Data(#"{"amount": 99.99}"#.utf8))
        #expect(row.amount.decimal == Decimal(string: "99.99"))
    }

    @Test @MainActor func autoSeededDemoPurgesBeforeFirstConfiguredSync() throws {
        let container = try ModelContainer(
            for: Client.self, Entry.self, Heading.self, SyncTombstone.self, ProjectIconPreference.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let suite = "earnline-tests-purge"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let inserted = SampleData.importBundledLedgerIfNeeded(context, defaults: defaults)
        #expect(inserted > 0)
        #expect(defaults.bool(forKey: SampleData.autoSeededDemoKey))

        let removed = try SampleData.purgeAutoSeededDemoIfNeeded(context, defaults: defaults)
        #expect(removed == inserted)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Client>()).isEmpty)
        // One-shot: a second call must be a no-op.
        #expect(try SampleData.purgeAutoSeededDemoIfNeeded(context, defaults: defaults) == 0)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test @MainActor func leakedProductionFixturesAreRemovedWithoutDeletingRealRows() throws {
        let container = try ModelContainer(
            for: Client.self, Entry.self, Heading.self, SyncTombstone.self, ProjectIconPreference.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let suite = "earnline-tests-fixture-cleanup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(SampleData.seedGenerated(context) > 0)
        #expect(SampleData.seedStress(context) > 0)

        let demoClientID = DeterministicID.uuid("earnline-seed-client:Acme Studio")
        let demoClient = try #require(
            context.fetch(FetchDescriptor<Client>()).first { $0.id == demoClientID }
        )
        let preservedEntry = Entry(amount: 42, task: "Real work kept", status: .paid)
        preservedEntry.client = demoClient
        context.insert(preservedEntry)

        let realClient = Client(name: "Real client")
        let realEntry = Entry(amount: 100, task: "Real line", status: .paid)
        realEntry.client = realClient
        context.insert(realClient)
        context.insert(realEntry)
        try context.save()

        #expect(try SampleData.cleanupLeakedProductionFixturesIfNeeded(context, defaults: defaults) > 0)

        let clients = try context.fetch(FetchDescriptor<Client>())
        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(clients.contains { $0.id == demoClientID })
        #expect(clients.contains { $0.id == realClient.id })
        #expect(clients.allSatisfy { !$0.name.hasPrefix("Stress Client ") })
        #expect(entries.map(\.id).contains(preservedEntry.id))
        #expect(entries.map(\.id).contains(realEntry.id))
        #expect(entries.count == 2)
        #expect(try SampleData.cleanupLeakedProductionFixturesIfNeeded(context, defaults: defaults) == 0)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
