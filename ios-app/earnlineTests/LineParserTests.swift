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
        #expect(entries.count == 29)
        #expect(entries.filter { $0.clientName == "Mikita" }.count == 25)
        #expect(entries.filter { $0.clientName == "bóra" }.count == 2)
        #expect(entries.filter { $0.clientName == "blackwave" }.count == 2)
        #expect(entries.filter { $0.currencyCode == "RUB" }.reduce(Decimal.zero) { $0 + $1.amount } == 35000)
        #expect(entries.filter { $0.currencyCode == "USD" }.reduce(Decimal.zero) { $0 + $1.amount } == 6160)
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

    @Test func rejectsImpossibleHoldDates() {
        // The lenient calendar must not roll these into a different real date.
        #expect(LineParser.parse("$140 Acme: Logo hold until 31.02").holdUntil == nil)
        #expect(LineParser.parse("$140 Acme: Logo hold until 07.25").holdUntil == nil) // US-style month 25
        #expect(LineParser.parse("$140 Acme: Logo hold until 14.03.26").holdUntil != nil)
    }

    @Test func readsEUFormatAmounts() {
        // Dot-grouped thousands with comma decimals, and the US form still works.
        #expect(LineParser.decimal(from: "1.000,50") == Decimal(string: "1000.50"))
        #expect(LineParser.decimal(from: "1.000.000,50") == Decimal(string: "1000000.50"))
        #expect(LineParser.decimal(from: "1,000.50") == Decimal(string: "1000.50"))
        #expect(LineParser.decimal(from: "1,000,000.50") == Decimal(string: "1000000.50"))

        let p = LineParser.parse("€1.000,50 Acme: Retainer")
        #expect(p.currencyCode == "EUR")
        #expect(p.amount == Decimal(string: "1000.50"))
    }

    @Test func doesNotTreatDueInsideAWordAsHold() {
        let p = LineParser.parse("$140 Acme: residue 12.05 cleanup")
        #expect(p.holdUntil == nil)
    }

    @Test func parsesTextCurrencyCodes() {
        let usd = LineParser.parse("Client 500 usd")
        #expect(usd.amount == 500)
        #expect(usd.currencyCode == "USD")
        #expect(usd.task == "Client")

        let eur = LineParser.parse("24k eur Acme: retainer", defaultCurrency: "USD")
        #expect(eur.amount == 24000)
        #expect(eur.currencyCode == "EUR")
        #expect(eur.project == "Acme")
    }

    @Test func parsesTrailingStatusWord() {
        let p = LineParser.parse("$500 Acme: Site pending")
        #expect(p.status == .inProgress)
        #expect(p.amount == 500)
        #expect(p.task == "Site")
    }

    @Test func parsesLeadingStatusWord() {
        let p = LineParser.parse("paid $300 Acme: Site")
        #expect(p.status == .paid)
        #expect(p.amount == 300)
    }

    @Test func emojiStatusWinsOverStatusWord() {
        let p = LineParser.parse("✅ $300 Acme: Site pending")
        #expect(p.status == .paid)
    }

    @Test func statusWordInsideTaskTextIsKept() {
        // "Paid search" is ad jargon, not a status marker — only standalone
        // words at the line's edges count, and this one is followed by text.
        let p = LineParser.parse("$300 Client: Paid search ads audit pending")
        #expect(p.status == .inProgress) // trailing "pending" is a marker…
        #expect(p.task == "Paid search ads audit") // …"Paid search" is not
    }

    @Test func parsesRussianStatusWord() {
        let p = LineParser.parse("оплачено 5 000 ₽ Acme: баннер")
        #expect(p.status == .paid)
        #expect(p.amount == 5000)
        #expect(p.currencyCode == "RUB")
    }

    @Test func midProseAmountIsNotCaptured() {
        // An amount leads or trails an income line; digits buried mid-prose
        // belong to the text.
        let p = LineParser.parse("refund the $500 deposit next week")
        #expect(p.amount == nil)
        #expect(p.task == "refund the $500 deposit next week")
    }

    @Test func zeroAmountIsNotCommittable() {
        #expect(!LineParser.parse("$0 Acme: comp work").isCommittable)
    }

    @Test func recognizesUkrainianMonthSectionHeadings() {
        let ref = date(year: 2026, month: 7, day: 2)
        let cal = Calendar.current

        let may = LineParser.sectionMonth("— Дохід за травень", referenceDate: ref)
        #expect(cal.component(.month, from: may!) == 5)
        #expect(cal.component(.year, from: may!) == 2026)

        // Genitive form + explicit year.
        let genitive = LineParser.sectionMonth("— Дохід за травня 2025", referenceDate: ref)
        #expect(cal.component(.month, from: genitive!) == 5)
        #expect(cal.component(.year, from: genitive!) == 2025)
    }

    @Test func recognizesMonthSectionHeadings() {
        let ref = date(year: 2026, month: 7, day: 2)
        let cal = Calendar.current

        let april = LineParser.sectionMonth("— Income for April", referenceDate: ref)
        let aprilComps = cal.dateComponents([.year, .month, .day], from: april!)
        #expect(aprilComps.year == 2026)
        #expect(aprilComps.month == 4)
        #expect(aprilComps.day == 1)

        // A month "after" the reference month reads as last year…
        let december = LineParser.sectionMonth("— Доходы за декабрь", referenceDate: ref)
        #expect(cal.component(.year, from: december!) == 2025)
        // …unless the year is explicit.
        let explicit = LineParser.sectionMonth("— Income for December 2024", referenceDate: ref)
        #expect(cal.component(.year, from: explicit!) == 2024)

        // Ordinary income lines are not sections, even if they name a month.
        #expect(LineParser.sectionMonth("+$240 April campaign: banners", referenceDate: ref) == nil)
    }

    @Test func ledgerBlockDatesLinesToTheirSection() {
        let ref = date(year: 2026, month: 7, day: 2)
        let block = """
        +$10 Before any section

        — Income for April
        +$220 Landing page
        """
        let lines = LineParser.parseLedgerBlock(block, referenceDate: ref)
        #expect(lines.count == 2)
        #expect(lines[0].date == nil)
        #expect(Calendar.current.component(.month, from: lines[1].date!) == 4)
    }

    /// A line with no amount and no `project: task` colon is prose. Its first
    /// word was being consumed as a status marker, which both lost the word and
    /// silently marked the line paid.
    @Test func leadingStatusWordStaysInPlainProse() {
        let p = LineParser.parse("Paid search ads audit")
        #expect(p.status == nil)
        #expect(p.task == "Paid search ads audit")
    }

    /// The same word still marks the line once it reads as an income line.
    @Test func leadingStatusWordIsAMarkerWhenTheLineHasAnAmountOrAColon() {
        let withColon = LineParser.parse("paid Acme: retainer")
        #expect(withColon.status == .paid)
        #expect(withColon.project == "Acme")
        #expect(withColon.task == "retainer")

        let withSymbol = LineParser.parse("paid $300 Site refresh")
        #expect(withSymbol.status == .paid)
        #expect(withSymbol.amount == 300)
        #expect(withSymbol.task == "Site refresh")

        let withBareAmount = LineParser.parse("pending 450 Site refresh")
        #expect(withBareAmount.status == .inProgress)
        #expect(withBareAmount.amount == 450)
    }

    /// A trailing word is unambiguous — nothing follows it — so it is consumed
    /// even without an amount or a colon.
    @Test func trailingStatusWordIsAlwaysAMarker() {
        let p = LineParser.parse("Acme retainer paid")
        #expect(p.status == .paid)
        #expect(p.task == "Acme retainer")
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
