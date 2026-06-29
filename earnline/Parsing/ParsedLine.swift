import Foundation

/// Structured result of understanding a freeform income line. Drives the
/// composer's live chips and the eventual `Entry`.
struct ParsedLine: Equatable {
    var amount: Decimal?
    var currencyCode: String = "USD"
    var project: String?
    var task: String = ""
    var holdUntil: Date?
    var status: EntryStatus?

    /// Enough information present to commit a real line.
    var isCommittable: Bool {
        amount != nil && (!(task.isEmpty) || project != nil)
    }
}
