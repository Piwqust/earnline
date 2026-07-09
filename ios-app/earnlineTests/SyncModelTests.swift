import Foundation
import SwiftData
import Testing
@testable import earnline

struct SyncModelTests {
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

    @Test @MainActor func identicalCurrenciesAreSeparatedAndSecondaryKeepsCents() {
        let app = AppModel()
        app.baseCurrencyCode = "EUR"
        app.secondaryCurrencyCode = "EUR"

        #expect(app.secondaryCurrencyCode != app.baseCurrencyCode)

        app.baseCurrencyCode = "USD"
        app.secondaryCurrencyCode = "RUB"
        app.rate = 89.125
        // The decimal separator follows the run locale (the formatter is
        // locale-aware); grouping is always the app's no-break space.
        let separator = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        #expect(app.secondaryString(Decimal(string: "99.50")!) == "8\u{00A0}867\(separator)94 ₽")
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
            for: Client.self, Entry.self, Heading.self, SyncTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let suite = "earnline-tests-purge"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let inserted = SampleData.importBundledLedgerIfNeeded(context, defaults: defaults)
        #expect(inserted > 0)
        #expect(defaults.bool(forKey: SampleData.autoSeededDemoKey))

        let removed = SampleData.purgeAutoSeededDemoIfNeeded(context, defaults: defaults)
        #expect(removed == inserted)
        #expect(try context.fetch(FetchDescriptor<Entry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Client>()).isEmpty)
        // One-shot: a second call must be a no-op.
        #expect(SampleData.purgeAutoSeededDemoIfNeeded(context, defaults: defaults) == 0)
        defaults.removePersistentDomain(forName: suite)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
