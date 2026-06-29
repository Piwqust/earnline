import Testing
import Foundation
@testable import earnline

struct LineParserTests {
    @Test func parsesDollarAmountProjectAndTask() {
        let p = LineParser.parse("+$240 LunaAI: 2 screens")
        #expect(p.amount == 240)
        #expect(p.currencyCode == "USD")
        #expect(p.project == "LunaAI")
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
        let p = LineParser.parse("⌛ $140 LunaAI: Logotype hold until 14.03.26")
        #expect(p.status == .inProgress)
        #expect(p.amount == 140)
        #expect(p.project == "LunaAI")
        #expect(p.task == "Logotype")
        let comps = Calendar.current.dateComponents([.day, .month, .year], from: p.holdUntil!)
        #expect(comps.day == 14)
        #expect(comps.month == 3)
        #expect(comps.year == 2026)
    }

    @Test func parsesSpaceGroupedThousands() {
        let p = LineParser.parse("$1 000 BlackWave: Telegram bot")
        #expect(p.amount == 1000)
        #expect(p.project == "BlackWave")
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
        let p = LineParser.parse("+ 11k₽ Winline: KVs")
        #expect(p.currencyCode == "RUB")
        #expect(p.amount == 11000)
        #expect(p.project == "Winline")
        #expect(p.task == "KVs")
    }

    @Test func parsesLeadingBareNumber() {
        let p = LineParser.parse("240 LunaAI: Two screens")
        #expect(p.amount == 240)
        #expect(p.project == "LunaAI")
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
        #expect(LineParser.parse("$240 LunaAI: 2 screens").isCommittable)
        #expect(!LineParser.parse("LunaAI: 2 screens").isCommittable)
    }

    @Test func parsesBundledIncomeLedger() {
        let entries = IncomeLedgerImporter.parse(IncomeLedgerImporter.bundledLedger, year: 2026)
        #expect(entries.count == 29)
        #expect(entries.filter { $0.clientName == "Mikita" }.count == 25)
        #expect(entries.filter { $0.clientName == "bóra" }.count == 2)
        #expect(entries.filter { $0.clientName == "blackwave" }.count == 2)
        #expect(entries.filter { $0.currencyCode == "RUB" }.reduce(Decimal.zero) { $0 + $1.amount } == 35000)
        #expect(entries.filter { $0.currencyCode == "USD" }.reduce(Decimal.zero) { $0 + $1.amount } == 6160)
    }
}
