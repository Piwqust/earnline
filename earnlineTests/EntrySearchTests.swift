import Foundation
import Testing
@testable import earnline

struct EntrySearchTests {
    private func entry(project: String? = nil, task: String = "", amount: Decimal = 0) -> Entry {
        Entry(amount: amount, project: project, task: task, status: .paid)
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
}
