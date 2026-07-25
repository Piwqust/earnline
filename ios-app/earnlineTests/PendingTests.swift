import Foundation
import Testing
@testable import earnline

@MainActor
struct PendingTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func pendingEntriesFilterInProgressAndSortByHold() {
        let app = AppModel()
        let client = Client(name: "Acme")
        let paid = Entry(amount: 1, task: "paid", status: .paid)
        let soon = Entry(amount: 1, task: "soon", holdUntil: date(2026, 7, 1), status: .inProgress)
        let later = Entry(amount: 1, task: "later", holdUntil: date(2026, 8, 1), status: .inProgress)
        let undated = Entry(amount: 1, task: "undated", status: .inProgress)
        client.entries = [paid, later, undated, soon]

        #expect(Insights.sortedByUrgency(client.entries).map(\.task) == ["soon", "later", "undated"])
    }

    @Test func isOverdueOnlyForPastInProgressHolds() {
        let app = AppModel()
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        #expect(app.insights.isOverdue(Entry(amount: 1, task: "x", holdUntil: yesterday, status: .inProgress)))
        #expect(!app.insights.isOverdue(Entry(amount: 1, task: "x", holdUntil: tomorrow, status: .inProgress)))
        #expect(!app.insights.isOverdue(Entry(amount: 1, task: "x", holdUntil: yesterday, status: .paid)))
        #expect(!app.insights.isOverdue(Entry(amount: 1, task: "x", status: .inProgress)))
    }

    @Test func desiredRequestsScheduleOnlyFutureInProgressHolds() {
        let now = date(2026, 6, 30)
        let future = Entry(amount: 1, task: "future", holdUntil: date(2026, 7, 5), status: .inProgress)
        let past = Entry(amount: 1, task: "past", holdUntil: date(2026, 6, 1), status: .inProgress)
        let paidFuture = Entry(amount: 1, task: "paid", holdUntil: date(2026, 7, 5), status: .paid)
        let noHold = Entry(amount: 1, task: "nohold", status: .inProgress)

        let requests = PendingNotifications.desiredRequests(
            for: [future, past, paidFuture, noHold], now: now
        )
        #expect(requests.count == 1)
        #expect(requests.first?.id == future.id.uuidString)
        #expect(requests.first?.dateComponents.day == 5)
        #expect(requests.first?.dateComponents.hour == 9)
    }

    @Test func dueTodayAfterNineAMGetsNoReminder() {
        let cal = Calendar.current
        let today = date(2026, 6, 30)
        let hold = Entry(amount: 1, task: "today", holdUntil: today, status: .inProgress)

        let morning = cal.date(byAdding: .hour, value: 8, to: today)!
        #expect(PendingNotifications.desiredRequests(for: [hold], now: morning).count == 1)

        // Past 09:00 the calendar trigger would be in the past (fires
        // immediately, again on every rebuild) — so it must be skipped.
        let afternoon = cal.date(byAdding: .hour, value: 15, to: today)!
        #expect(PendingNotifications.desiredRequests(for: [hold], now: afternoon).isEmpty)
    }
}
