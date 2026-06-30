import Foundation
import Testing
@testable import earnline

@MainActor
struct InsightsTests {
    private func makeApp() -> AppModel {
        let app = AppModel()
        app.baseCurrencyCode = "USD"
        app.secondaryCurrencyCode = "RUB"
        app.rate = 100
        return app
    }

    @Test func monthlySeriesHasRequestedLengthAndExcludesCanceled() {
        let app = makeApp()
        let client = Client(name: "Acme")
        let thisMonth = DateFormat.monthStart(of: .now)
        client.entries = [
            Entry(amount: 100, task: "paid", date: thisMonth, status: .paid),
            Entry(amount: 50, task: "progress", date: thisMonth, status: .inProgress),
            Entry(amount: 999, task: "canceled", date: thisMonth, status: .canceled),
        ]

        let series = app.monthlySeries([client], lastNMonths: 6)
        #expect(series.count == 6)
        #expect(series.last?.total == 150) // paid + inProgress, canceled excluded
        #expect(series.dropLast().allSatisfy { $0.total == 0 }) // earlier months empty
    }

    @Test func monthlySeriesSumsSecondaryCurrencyViaRate() {
        let app = makeApp()
        let client = Client(name: "Acme")
        let thisMonth = DateFormat.monthStart(of: .now)
        client.entries = [
            Entry(amount: 5000, currencyCode: "RUB", task: "rub", date: thisMonth, status: .paid),
        ]
        // 5000 RUB / 100 = 50 base
        #expect(app.monthlySeries([client], lastNMonths: 3).last?.total == 50)
    }

    @Test func topClientsRankedByEarnedTotal() {
        let app = makeApp()
        let thisMonth = DateFormat.monthStart(of: .now)
        let a = Client(name: "A")
        let b = Client(name: "B")
        a.entries = [Entry(amount: 100, task: "x", date: thisMonth, status: .paid)]
        b.entries = [Entry(amount: 300, task: "y", date: thisMonth, status: .paid)]

        let top = app.topClients([a, b], lastNMonths: 3)
        #expect(top.count == 2)
        #expect(top.first?.client.name == "B")
        #expect(top.first?.total == 300)
    }
}
