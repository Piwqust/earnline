import Foundation
import SwiftData
import Testing
@testable import earnline

@MainActor
struct MonthReviewTests {
    @Test func deterministicMonthIdentityNormalizesJanuaryAndSoftCloseReopens() throws {
        let container = try ModelContainer(
            for: MonthReview.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let calendar = Calendar.current
        let januaryFirst = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let januaryLast = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))!
        let closeDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 9))!

        #expect(MonthReview.id(for: januaryFirst) == MonthReview.id(for: januaryLast))
        // Shared with `monthReview.test.ts`: catches accidental namespace or
        // deterministic-ID drift between the iOS and web sync clients.
        #expect(MonthReview.id(for: januaryFirst).uuidString.lowercased()
                    == "f1010a14-d16f-52d3-92b6-57d1f655d082")

        let review = try MonthReviewStore.close(
            monthContaining: januaryLast,
            note: "Closed after delivery",
            in: context,
            at: closeDate
        )
        try context.save()
        #expect(SyncDateCodec.dayString(review.monthStart) == "2026-01-01")
        #expect(review.closedAt == closeDate)
        #expect(review.syncState == .dirty)

        let reopenResult = try MonthReviewStore.reopen(
            monthContaining: januaryFirst,
            in: context,
            at: closeDate.addingTimeInterval(60)
        )
        let reopened = try #require(reopenResult)
        try context.save()
        #expect(reopened.id == review.id)
        #expect(reopened.note == "Closed after delivery")
        #expect(reopened.closedAt == nil)
        #expect(reopened.syncState == .dirty)
    }

    @Test func noteLimitRejectsOversizedTextBeforeMutatingTheStore() throws {
        let container = try ModelContainer(
            for: MonthReview.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        #expect(throws: MonthReviewError.noteTooLong(maximum: MonthReview.maximumNoteLength)) {
            try MonthReviewStore.close(
                monthContaining: .now,
                note: String(repeating: "x", count: MonthReview.maximumNoteLength + 1),
                in: context
            )
        }
        #expect(try context.fetch(FetchDescriptor<MonthReview>()).isEmpty)
    }

    @Test func noteLimitUsesSharedUnicodeScalarRule() {
        #expect(MonthReview.isValid(note: String(repeating: "🪙", count: MonthReview.maximumNoteLength)))
        #expect(!MonthReview.isValid(note: String(repeating: "🪙", count: MonthReview.maximumNoteLength + 1)))
    }
}
