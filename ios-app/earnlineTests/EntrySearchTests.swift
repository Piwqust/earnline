import Foundation
import Testing
@testable import earnline

struct EntrySearchTests {
    private func entry(project: String? = nil,
                       task: String = "",
                       amount: Decimal = 0,
                       date: Date = .now,
                       status: EntryStatus = .paid) -> Entry {
        Entry(amount: amount, project: project, task: task, date: date, status: status)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(EntrySearch.matches(entry(task: "anything"), query: "  ", clientName: "Acme"))
    }

    @Test func matchesClientNameCaseInsensitive() {
        let e = entry(task: "Two screens")
        #expect(EntrySearch.matches(e, query: "ACME", clientName: "Acme Studio"))
    }

    @Test func matchesProjectAndTask() {
        let e = entry(project: "Launch Kit", task: "Onboarding screens")
        #expect(EntrySearch.matches(e, query: "launch", clientName: nil))
        #expect(EntrySearch.matches(e, query: "onboard", clientName: nil))
    }

    @Test func matchesAmountDigits() {
        let e = entry(task: "Landing page", amount: 240)
        #expect(EntrySearch.matches(e, query: "24", clientName: nil))
        #expect(EntrySearch.matches(e, query: "240", clientName: nil))
    }

    @Test func ignoresDiacritics() {
        let e = entry(task: "Cafe banner")
        #expect(EntrySearch.matches(e, query: "café", clientName: nil))
    }

    @Test func returnsFalseWhenNothingMatches() {
        let e = entry(project: "Launch Kit", task: "Landing page", amount: 240)
        #expect(EntrySearch.matches(e, query: "zzz", clientName: "Acme") == false)
    }

    // MARK: Date text

    @Test func matchesMonthNameYearAndCombination() {
        let e = entry(task: "Landing page", date: date(2026, 3, 14))
        #expect(EntrySearch.matches(e, query: "march", clientName: nil))
        #expect(EntrySearch.matches(e, query: "March 2026", clientName: nil))
        #expect(EntrySearch.matches(e, query: "2026", clientName: nil))
        #expect(EntrySearch.matches(e, query: "may", clientName: nil) == false)
    }

    @Test func shortQueriesDoNotMatchDateText() {
        let e = entry(task: "Landing page", date: date(2026, 3, 14))
        #expect(EntrySearch.matches(e, query: "ma", clientName: nil) == false)
    }

    // MARK: Tokens

    @Test func inactiveFilterMatchesEverything() {
        let filter = EntrySearch.Filter(query: " ")
        #expect(filter.isActive == false)
        #expect(filter.matches(entry(task: "anything"), clientName: nil))
    }

    @Test func monthTokenFiltersByCalendarMonth() {
        let filter = EntrySearch.Filter(query: "", tokens: [.month(date(2026, 3, 1))])
        #expect(filter.isActive)
        #expect(filter.matches(entry(date: date(2026, 3, 14)), clientName: nil))
        #expect(filter.matches(entry(date: date(2026, 4, 2)), clientName: nil) == false)
        #expect(filter.matches(entry(date: date(2025, 3, 14)), clientName: nil) == false)
    }

    @Test func monthAndYearTokensFormOneDateGroup() {
        let filter = EntrySearch.Filter(query: "", tokens: [.month(date(2026, 3, 1)), .year(2025)])
        #expect(filter.matches(entry(date: date(2026, 3, 14)), clientName: nil))
        #expect(filter.matches(entry(date: date(2025, 8, 2)), clientName: nil))
        #expect(filter.matches(entry(date: date(2026, 4, 2)), clientName: nil) == false)
    }

    @Test func statusTokenFilters() {
        let filter = EntrySearch.Filter(query: "", tokens: [.status(.inProgress)])
        #expect(filter.matches(entry(status: .inProgress), clientName: nil))
        #expect(filter.matches(entry(status: .paid), clientName: nil) == false)
    }

    @Test func clientTokenMatchesProvidedClientID() {
        let acme = UUID()
        let filter = EntrySearch.Filter(query: "", tokens: [.client(acme, name: "Acme")])
        #expect(filter.matches(entry(), clientID: acme, clientName: "Acme"))
        #expect(filter.matches(entry(), clientID: UUID(), clientName: "Other") == false)
        #expect(filter.matches(entry(), clientID: nil, clientName: nil) == false)
    }

    @Test func projectTokenFiltersCaseInsensitive() {
        let filter = EntrySearch.Filter(query: "", tokens: [.project("Launch Kit")])
        #expect(filter.matches(entry(project: "launch kit"), clientName: nil))
        #expect(filter.matches(entry(project: "Other"), clientName: nil) == false)
        #expect(filter.matches(entry(), clientName: nil) == false)
    }

    @Test func tokenGroupsCombineWithEachOtherAndText() {
        let filter = EntrySearch.Filter(
            query: "landing",
            tokens: [.month(date(2026, 3, 1)), .status(.paid)]
        )
        #expect(filter.matches(entry(task: "Landing page", date: date(2026, 3, 14)), clientName: nil))
        // Wrong month, matching text and status.
        #expect(filter.matches(entry(task: "Landing page", date: date(2026, 4, 2)), clientName: nil) == false)
        // Right month and status, text misses.
        #expect(filter.matches(entry(task: "Banner", date: date(2026, 3, 14)), clientName: nil) == false)
        // Right month and text, wrong status.
        #expect(filter.matches(entry(task: "Landing page", date: date(2026, 3, 14), status: .canceled),
                               clientName: nil) == false)
    }

    // MARK: Filter inventory

    @Test func filterSourceListsDistinctYearsNewestFirstAndMonthsPerYear() {
        var source = EntrySearch.FilterSource()
        source.months = [date(2026, 3, 1), date(2026, 2, 1), date(2025, 12, 1)]
        #expect(source.years == [2026, 2025])
        #expect(source.months(in: 2026) == [date(2026, 3, 1), date(2026, 2, 1)])
        #expect(source.months(in: 2025) == [date(2025, 12, 1)])
    }
}
