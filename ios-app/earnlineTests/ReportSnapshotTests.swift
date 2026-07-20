import Foundation
import Testing
import UIKit
@testable import earnline

struct ReportSnapshotTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var converter: CurrencyConverter {
        CurrencyConverter(baseCurrencyCode: "USD", secondaryCurrencyCode: "RUB", rate: 83)
    }

    private func entry(
        id: UUID = UUID(),
        clientID: UUID,
        clientName: String,
        amount: Decimal,
        currency: String,
        task: String = "Design work",
        date: Date,
        status: ReportEntryStatus = .paid
    ) -> ReportEntry {
        ReportEntry(
            id: id,
            clientID: clientID,
            clientName: clientName,
            amount: amount,
            currencyCode: currency,
            project: "Launch",
            task: task,
            date: date,
            holdUntil: nil,
            status: status
        )
    }

    @Test func originalCurrenciesStayVisibleWhenUSDConversionExcludesAThirdCurrency() {
        let acme = UUID()
        let snapshot = ReportSnapshotBuilder(input: .init(
            entries: [
                entry(clientID: acme, clientName: "Acme", amount: 100, currency: "USD", date: date(2026, 7, 2)),
                entry(clientID: acme, clientName: "Acme", amount: 8_300, currency: "RUB", date: date(2026, 7, 3), status: .inProgress),
                entry(clientID: acme, clientName: "Acme", amount: 50, currency: "EUR", date: date(2026, 7, 4)),
                entry(clientID: acme, clientName: "Acme", amount: 999, currency: "EUR", date: date(2026, 7, 5), status: .canceled),
            ],
            converter: converter
        )).snapshot(
            scope: .month(containing: date(2026, 7, 1)),
            audience: .personal,
            generatedAt: date(2026, 7, 31)
        )

        #expect(snapshot.originalCurrencyTotals.map(\.currencyCode) == ["EUR", "RUB", "USD"])
        #expect(snapshot.originalCurrencyTotals.first(where: { $0.currencyCode == "EUR" })?.amount == 50)
        #expect(snapshot.paid.entryCount == 2)
        #expect(snapshot.inProgress.entryCount == 1)
        #expect(snapshot.canceledEntryCount == 1)
        #expect(snapshot.usdEquivalent?.amount == 200)
        #expect(snapshot.usdEquivalent?.excludedCurrencyTotals.map(\.currencyCode) == ["EUR"])
        #expect(snapshot.usdEquivalent?.excludedCurrencyTotals.first?.amount == 50)
    }

    @Test func lastYearComparisonKeepsEachOriginalCurrencySeparateAcrossJanuary() throws {
        let acme = UUID()
        let snapshot = ReportSnapshotBuilder(input: .init(
            entries: [
                entry(clientID: acme, clientName: "Acme", amount: 200, currency: "USD", date: date(2026, 1, 8)),
                entry(clientID: acme, clientName: "Acme", amount: 50, currency: "EUR", date: date(2026, 1, 9)),
                entry(clientID: acme, clientName: "Acme", amount: 100, currency: "USD", date: date(2025, 1, 8)),
                entry(clientID: acme, clientName: "Acme", amount: 75, currency: "EUR", date: date(2025, 1, 9)),
            ],
            converter: converter
        )).snapshot(
            scope: .month(containing: date(2026, 1, 20)),
            audience: .personal,
            generatedAt: date(2026, 1, 31)
        )

        let comparison = try #require(snapshot.lastYearComparison)
        #expect(Calendar.current.isDate(comparison.period.start, equalTo: date(2025, 1, 1), toGranularity: .month))
        #expect(comparison.currencyChanges.map(\.currencyCode) == ["EUR", "USD"])
        #expect(comparison.currencyChanges.first(where: { $0.currencyCode == "USD" })?.difference == 100)
        #expect(comparison.currencyChanges.first(where: { $0.currencyCode == "EUR" })?.difference == -25)
        #expect(comparison.usdEquivalent?.difference == 100)
    }

    @Test func clientReportDoesNotLeakOtherClientsPersonalNotesOrYearComparison() {
        let acme = UUID()
        let northstar = UUID()
        let snapshot = ReportSnapshotBuilder(input: .init(
            entries: [
                entry(clientID: acme, clientName: "Acme", amount: 100, currency: "USD", date: date(2026, 7, 2)),
                entry(clientID: northstar, clientName: "Northstar", amount: 300, currency: "USD", date: date(2026, 7, 3)),
                entry(clientID: acme, clientName: "Acme", amount: 80, currency: "USD", date: date(2025, 7, 2)),
            ],
            eventNotes: [
                .init(id: UUID(), text: "Internal note", date: date(2026, 7, 1)),
            ],
            converter: converter
        )).snapshot(
            scope: .month(containing: date(2026, 7, 1)),
            audience: .client(id: acme, name: "Acme"),
            generatedAt: date(2026, 7, 31)
        )

        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries.first?.clientID == acme)
        #expect(snapshot.eventNotes.isEmpty)
        #expect(snapshot.lastYearComparison == nil)
        #expect(snapshot.clientCount == 1)
    }

    @Test func USDTotalIsOmittedWhenUSDIsNotAConfiguredConversionCurrency() {
        let acme = UUID()
        let snapshot = ReportSnapshotBuilder(input: .init(
            entries: [
                entry(clientID: acme, clientName: "Acme", amount: 100, currency: "EUR", date: date(2026, 7, 2)),
                entry(clientID: acme, clientName: "Acme", amount: 9_000, currency: "RUB", date: date(2026, 7, 3)),
            ],
            converter: CurrencyConverter(baseCurrencyCode: "EUR", secondaryCurrencyCode: "RUB", rate: 90)
        )).snapshot(
            scope: .month(containing: date(2026, 7, 1)),
            audience: .personal
        )

        #expect(snapshot.usdEquivalent == nil)
        #expect(snapshot.originalCurrencyTotals.map(\.currencyCode) == ["EUR", "RUB"])
    }

    @Test func monthReviewOnlyAppearsOnAPersonalMonthlyReport() {
        let acme = UUID()
        let review = ReportMonthReview(
            monthStart: date(2026, 7, 1),
            note: "Wrapped launch work",
            closedAt: date(2026, 8, 1)
        )
        let input = ReportSnapshotInput(
            entries: [entry(clientID: acme, clientName: "Acme", amount: 100, currency: "USD", date: date(2026, 7, 2))],
            monthReviews: [review],
            converter: converter
        )
        let builder = ReportSnapshotBuilder(input: input)

        let personal = builder.snapshot(scope: .month(containing: date(2026, 7, 1)), audience: .personal)
        let client = builder.snapshot(scope: .month(containing: date(2026, 7, 1)), audience: .client(id: acme, name: "Acme"))
        let range = builder.snapshot(scope: .dateRange(start: date(2026, 7, 1), end: date(2026, 7, 31)), audience: .personal)

        #expect(personal.monthReview == review)
        #expect(client.monthReview == nil)
        #expect(range.monthReview == nil)
    }

    @Test @MainActor func rendererCreatesExactlySizedMultiplePNGCardsAndCleanupIsExplicit() throws {
        let acme = UUID()
        let entries = (0..<12).map { index in
            entry(
                clientID: acme,
                clientName: "Acme",
                amount: Decimal(index + 1) * 100,
                currency: "USD",
                task: String(repeating: "A carefully documented design decision ", count: 12),
                date: date(2026, 7, index + 1)
            )
        }
        let snapshot = ReportSnapshotBuilder(input: .init(entries: entries, converter: converter)).snapshot(
            scope: .month(containing: date(2026, 7, 1)),
            audience: .personal,
            generatedAt: date(2026, 7, 31)
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try ReportCardRenderer.render(snapshot: snapshot, directory: directory)

        #expect(result.cards.count > 1)
        #expect(result.cards.allSatisfy { $0.image.size == ReportCardRenderer.imageSize })
        #expect(result.export.fileURLs.count == result.cards.count)
        #expect(result.export.fileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        try result.export.removeFiles()
        #expect(result.export.fileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}
