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

    @Test func monthPaceProjectsLinearly() {
        // July 15 of 31 days: 150 earned → 310 projected.
        #expect(AppModel.monthPace(total: 150, now: date(2026, 7, 15)) == 310)
        // February (28 days in 2026), halfway: doubles.
        #expect(AppModel.monthPace(total: 140, now: date(2026, 2, 14)) == 280)
    }

    @Test func monthPaceSuppressedEarlyAndWhenEmpty() {
        #expect(AppModel.monthPace(total: 500, now: date(2026, 7, 1)) == nil)
        #expect(AppModel.monthPace(total: 500, now: date(2026, 7, 2)) == nil)
        #expect(AppModel.monthPace(total: 500, now: date(2026, 7, 3)) != nil)
        #expect(AppModel.monthPace(total: 0, now: date(2026, 7, 15)) == nil)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Daily heatmap

    @Test func dailyEarningsLandsWholeAmountOnLineDate() {
        let app = makeApp()
        let client = Client(name: "Acme")
        let day = date(2026, 7, 10)
        client.entries = [
            Entry(amount: 200, task: "paid", date: day, status: .paid),
            Entry(amount: 999, task: "canceled", date: day, status: .canceled),
        ]

        let map = app.dailyEarnings([client], from: date(2026, 7, 1), through: date(2026, 7, 31))
        #expect(map[Calendar.current.startOfDay(for: day)] == 200) // canceled excluded
        #expect(map.values.reduce(Decimal.zero, +) == 200)         // nothing on any other day
    }

    @Test func dailyEarningsSpreadsAHoldEvenlyAcrossItsSpan() {
        let app = makeApp()
        let client = Client(name: "Acme")
        // 300 held across the inclusive 3-day span 10–12 July → 100 per day.
        client.entries = [
            Entry(amount: 300, task: "held", date: date(2026, 7, 10),
                  holdUntil: date(2026, 7, 12), status: .inProgress),
        ]

        let map = app.dailyEarnings([client], from: date(2026, 7, 1), through: date(2026, 7, 31))
        let cal = Calendar.current
        #expect(map[cal.startOfDay(for: date(2026, 7, 10))] == 100)
        #expect(map[cal.startOfDay(for: date(2026, 7, 11))] == 100)
        #expect(map[cal.startOfDay(for: date(2026, 7, 12))] == 100)
        #expect(map[cal.startOfDay(for: date(2026, 7, 9))] == nil)  // before the span
        #expect(map[cal.startOfDay(for: date(2026, 7, 13))] == nil) // after the span
        #expect(map.values.reduce(Decimal.zero, +) == 300)
    }

    @Test func dailyEarningsClipsAHoldToTheRequestedWindow() {
        let app = makeApp()
        let client = Client(name: "Acme")
        // 400 held across 8 days (28 Jun – 5 Jul); only the 3 July days fall
        // inside the window, so only their slices are counted.
        client.entries = [
            Entry(amount: 400, task: "held", date: date(2026, 6, 28),
                  holdUntil: date(2026, 7, 5), status: .inProgress),
        ]

        let map = app.dailyEarnings([client], from: date(2026, 7, 1), through: date(2026, 7, 31))
        #expect(map.count == 5) // 1–5 July
        #expect(map.values.allSatisfy { $0 == 50 }) // 400 / 8 days
    }

    @Test func dayContributionsFlagHeldSlices() {
        let app = makeApp()
        let client = Client(name: "Acme")
        client.entries = [
            Entry(amount: 300, task: "held", date: date(2026, 7, 10),
                  holdUntil: date(2026, 7, 12), status: .inProgress),
            Entry(amount: 80, task: "paid", date: date(2026, 7, 11), status: .paid),
        ]

        let rows = app.dayContributions(on: date(2026, 7, 11), clients: [client])
        #expect(rows.count == 2)
        #expect(rows.first?.amount == 100)        // largest first: the held slice
        #expect(rows.first?.isHeldSlice == true)
        #expect(rows.last?.amount == 80)
        #expect(rows.last?.isHeldSlice == false)
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
