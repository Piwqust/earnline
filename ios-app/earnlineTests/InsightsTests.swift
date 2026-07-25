import Foundation
import Testing
@testable import earnline

/// Daily-earnings behaviour: how one line lands on the calendar, and what the
/// tapped-day breakdown reports.
///
/// The per-day spreading tests used to run against `Insights.dailyEarnings`,
/// which no screen called any more — `InsightsDashboardSnapshot` computes these
/// figures now. They were moved onto the dashboard rather than deleted with it:
/// spreading a held amount evenly across its span, and clipping that span to the
/// visible window, is the subtle part and it is still live code.
@MainActor
struct InsightsTests {
    private let converter = CurrencyConverter(
        baseCurrencyCode: "USD",
        secondaryCurrencyCode: "RUB",
        rate: 100
    )

    private func dashboard(_ clients: [Client], windowMonths: Int = 12, now: Date) -> InsightsDashboardSnapshot {
        InsightsDashboardInput(clients: clients, converter: converter)
            .dashboardSnapshot(windowMonths: windowMonths, now: now)
    }

    // MARK: Daily heatmap

    @Test func dailyEarningsLandsWholeAmountOnLineDate() {
        let client = Client(name: "Acme")
        let day = date(2026, 7, 10)
        client.entries = [
            Entry(amount: 200, task: "paid", date: day, status: .paid),
            Entry(amount: 999, task: "canceled", date: day, status: .canceled),
        ]

        let map = dashboard([client], now: date(2026, 7, 11)).dailyEarnings
        #expect(map[Calendar.current.startOfDay(for: day)] == 200) // canceled excluded
        #expect(map.values.reduce(Decimal.zero, +) == 200)         // nothing on any other day
    }

    @Test func dailyEarningsSpreadsAHoldEvenlyAcrossItsSpan() {
        let client = Client(name: "Acme")
        // 300 held across the inclusive 3-day span 10–12 July → 100 per day.
        client.entries = [
            Entry(amount: 300, task: "held", date: date(2026, 7, 10),
                  holdUntil: date(2026, 7, 12), status: .inProgress),
        ]

        let map = dashboard([client], now: date(2026, 7, 11)).dailyEarnings
        let cal = Calendar.current
        #expect(map[cal.startOfDay(for: date(2026, 7, 10))] == 100)
        #expect(map[cal.startOfDay(for: date(2026, 7, 11))] == 100)
        #expect(map[cal.startOfDay(for: date(2026, 7, 12))] == 100)
        #expect(map[cal.startOfDay(for: date(2026, 7, 9))] == nil)  // before the span
        #expect(map[cal.startOfDay(for: date(2026, 7, 13))] == nil) // after the span
        #expect(map.values.reduce(Decimal.zero, +) == 300)
    }

    @Test func dailyEarningsClipsAHoldToTheVisibleWindow() {
        let client = Client(name: "Acme")
        // 400 held across 8 days (28 Jun – 5 Jul). With a one-month window only
        // the 5 July days are visible, so only their slices are counted — but
        // each slice is still 400/8, not 400/5.
        client.entries = [
            Entry(amount: 400, task: "held", date: date(2026, 6, 28),
                  holdUntil: date(2026, 7, 5), status: .inProgress),
        ]

        let map = dashboard([client], windowMonths: 1, now: date(2026, 7, 11)).dailyEarnings
        #expect(map.count == 5) // 1–5 July
        #expect(map.values.allSatisfy { $0 == 50 }) // 400 / 8 days
    }

    @Test func dayContributionsFlagHeldSlices() {
        let client = Client(name: "Acme")
        client.entries = [
            Entry(amount: 300, task: "held", date: date(2026, 7, 10),
                  holdUntil: date(2026, 7, 12), status: .inProgress),
            Entry(amount: 80, task: "paid", date: date(2026, 7, 11), status: .paid),
        ]

        let rows = Insights(converter: converter)
            .dayContributions(on: date(2026, 7, 11), candidates: client.entries)
        #expect(rows.count == 2)
        #expect(rows.first?.amount == 100)        // largest first: the held slice
        #expect(rows.first?.isHeldSlice == true)
        #expect(rows.last?.amount == 80)
        #expect(rows.last?.isHeldSlice == false)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
