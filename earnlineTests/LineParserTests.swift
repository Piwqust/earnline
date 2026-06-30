import Testing
import Foundation
@testable import earnline

struct LineParserTests {
    @Test func parsesDollarAmountProjectAndTask() {
        let p = LineParser.parse("+$240 Acme: 2 screens")
        #expect(p.amount == 240)
        #expect(p.currencyCode == "USD")
        #expect(p.project == "Acme")
        #expect(p.task == "2 screens")
    }

    @Test func parsesPaidMarker() {
        let p = LineParser.parse("✅ $300 Studio X: Landing page")
        #expect(p.status == .paid)
        #expect(p.amount == 300)
        #expect(p.project == "Studio X")
        #expect(p.task == "Landing page")
    }

    @Test func parsesHoldUntilDate() {
        let p = LineParser.parse("⌛ $140 Acme: Logotype hold until 14.03.26")
        #expect(p.status == .inProgress)
        #expect(p.amount == 140)
        #expect(p.project == "Acme")
        #expect(p.task == "Logotype")
        let comps = Calendar.current.dateComponents([.day, .month, .year], from: p.holdUntil!)
        #expect(comps.day == 14)
        #expect(comps.month == 3)
        #expect(comps.year == 2026)
    }

    @Test func holdDateWithoutYearRollsIntoFutureYear() {
        let reference = date(year: 2026, month: 12, day: 20)
        let p = LineParser.parse("$140 Acme: Logotype hold 14.01", referenceDate: reference)
        let comps = Calendar.current.dateComponents([.day, .month, .year], from: p.holdUntil!)
        #expect(comps.day == 14)
        #expect(comps.month == 1)
        #expect(comps.year == 2027)
    }

    @Test func holdDateWithoutYearKeepsFutureDateInCurrentYear() {
        let reference = date(year: 2026, month: 1, day: 3)
        let p = LineParser.parse("$140 Acme: Logotype hold 14.01", referenceDate: reference)
        let comps = Calendar.current.dateComponents([.day, .month, .year], from: p.holdUntil!)
        #expect(comps.day == 14)
        #expect(comps.month == 1)
        #expect(comps.year == 2026)
    }

    @Test func parsesSpaceGroupedThousands() {
        let p = LineParser.parse("$1 000 Northstar: Telegram bot")
        #expect(p.amount == 1000)
        #expect(p.project == "Northstar")
    }

    @Test func parsesCommaThousands() {
        let p = LineParser.parse("$1,250 Acme: Website")
        #expect(p.amount == 1250)
    }

    @Test func parsesDecimalAmount() {
        let p = LineParser.parse("$99.50 Acme: Fix")
        #expect(p.amount == Decimal(string: "99.5"))
    }

    @Test func parsesRubleSuffix() {
        let p = LineParser.parse("12 000 ₽ Local: Banner")
        #expect(p.currencyCode == "RUB")
        #expect(p.amount == 12000)
    }

    @Test func parsesThousandsSuffixBeforeCurrency() {
        let p = LineParser.parse("24k ₽")
        #expect(p.currencyCode == "RUB")
        #expect(p.amount == 24000)
    }

    @Test func parsesThousandsSuffixTightToCurrency() {
        let p = LineParser.parse("+ 11k₽ River: KVs")
        #expect(p.currencyCode == "RUB")
        #expect(p.amount == 11000)
        #expect(p.project == "River")
        #expect(p.task == "KVs")
    }

    @Test func parsesLeadingBareNumber() {
        let p = LineParser.parse("240 Acme: Two screens")
        #expect(p.amount == 240)
        #expect(p.project == "Acme")
    }

    @Test func noColonMeansTaskOnly() {
        let p = LineParser.parse("$50 quick fix")
        #expect(p.amount == 50)
        #expect(p.project == nil)
        #expect(p.task == "quick fix")
    }

    @Test func shortDigitIsNotMistakenForAmount() {
        let p = LineParser.parse("2 screens for the homepage")
        #expect(p.amount == nil)
        #expect(p.task == "2 screens for the homepage")
    }

    @Test func committableRequiresAmountAndText() {
        #expect(LineParser.parse("$240 Acme: 2 screens").isCommittable)
        #expect(!LineParser.parse("Acme: 2 screens").isCommittable)
    }

    @Test func parsesBundledIncomeLedger() {
        let entries = IncomeLedgerImporter.parse(IncomeLedgerImporter.bundledLedger, year: 2026)
        #expect(entries.count == 7)
        #expect(entries.filter { $0.clientName == "Acme Studio" }.count == 3)
        #expect(entries.filter { $0.clientName == "Northstar Labs" }.count == 2)
        #expect(entries.filter { $0.clientName == "River House" }.count == 2)
        #expect(entries.filter { $0.currencyCode == "RUB" }.reduce(Decimal.zero) { $0 + $1.amount } == 35000)
        #expect(entries.filter { $0.currencyCode == "USD" }.reduce(Decimal.zero) { $0 + $1.amount } == Decimal(string: "949.50")!)
    }

    @Test func parseBlockSplitsLinesAndFlagsCommittable() {
        let block = """
        +$240 Acme: 2 screens

        ⌛ $140 Acme: Logotype
        just a note with no amount
        """
        let lines = LineParser.parseBlock(block)
        #expect(lines.count == 3) // blank line dropped
        #expect(lines.filter(\.isCommittable).count == 2) // the note has no amount
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
