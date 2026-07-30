import Foundation
import SwiftData

/// A soft month close kept alongside the ledger rather than inside its entries.
/// The deterministic identifier means every client updates one shared review
/// for a calendar month instead of creating duplicates while offline.
@Model
final class MonthReview {
    static let maximumNoteLength = 280

    @Attribute(.unique) var id: UUID
    /// Canonical first calendar day of the reviewed month, stored at local noon
    /// like other synced day values so re-encoding stays on the same day.
    var monthStart: Date
    var note: String
    /// `nil` means the user reopened the month. The row remains synced so a
    /// reopened review cannot be mistaken for a deleted review on another device.
    var closedAt: Date?
    var createdAt: Date
    var updatedAt: Date?
    var syncStateRaw: String?
    var lastSyncedAt: Date?

    init(id: UUID? = nil,
         monthStart: Date,
         note: String = "",
         closedAt: Date? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         syncState: SyncState = .dirty,
         lastSyncedAt: Date? = nil) {
        let normalizedMonthStart = Self.monthStart(of: monthStart)
        self.id = id ?? Self.id(for: normalizedMonthStart)
        self.monthStart = normalizedMonthStart
        self.note = note
        self.closedAt = closedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStateRaw = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
    }

    static func monthStart(of date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month], from: date)
        components.day = 1
        components.hour = 12
        return Calendar.current.date(from: components) ?? DateFormat.monthStart(of: date)
    }

    static func id(for monthStart: Date) -> UUID {
        DeterministicID.uuid("earnline-month-review:\(SyncDateCodec.dayString(Self.monthStart(of: monthStart)))")
    }

    static func isValid(note: String) -> Bool {
        // Swift's `String.count` measures grapheme clusters while JS counts
        // UTF-16 code units. Keep the shared 280-character wire/storage
        // rule in Unicode scalars so iOS, web, and Postgres accept the same
        // Russian text and emoji notes.
        note.unicodeScalars.count <= maximumNoteLength
    }
}

enum MonthReviewError: LocalizedError, Equatable {
    case noteTooLong(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .noteTooLong(let maximum):
            return "A month note can contain up to \(maximum) characters."
        }
    }
}

/// The sole mutation boundary for soft-closing and reopening a month. It does
/// not save the context so callers retain Earnline's existing save/sync/error
/// contract through `LedgerMutationStore.save(_:)`.
@MainActor
enum MonthReviewStore {
    static func review(forMonthContaining date: Date,
                       in context: ModelContext) throws -> MonthReview? {
        let id = MonthReview.id(for: date)
        return try context.fetch(FetchDescriptor<MonthReview>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    @discardableResult
    static func close(monthContaining date: Date,
                      note: String,
                      in context: ModelContext,
                      at closedAt: Date = .now) throws -> MonthReview {
        try validate(note: note)
        if let existing = try review(forMonthContaining: date, in: context) {
            existing.note = note
            existing.closedAt = closedAt
            existing.markDirty(at: closedAt)
            return existing
        }

        let review = MonthReview(monthStart: date, note: note, closedAt: closedAt,
                                 createdAt: closedAt, updatedAt: closedAt)
        context.insert(review)
        return review
    }

    @discardableResult
    static func reopen(monthContaining date: Date,
                       in context: ModelContext,
                       at reopenedAt: Date = .now) throws -> MonthReview? {
        guard let review = try review(forMonthContaining: date, in: context) else { return nil }
        guard review.closedAt != nil else { return review }
        review.closedAt = nil
        review.markDirty(at: reopenedAt)
        return review
    }

    static func validate(note: String) throws {
        guard MonthReview.isValid(note: note) else {
            throw MonthReviewError.noteTooLong(maximum: MonthReview.maximumNoteLength)
        }
    }
}
