import Foundation
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
        #expect(app.secondaryString(Decimal(string: "99.50")!) == "8\u{00A0}867.94 ₽")
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
