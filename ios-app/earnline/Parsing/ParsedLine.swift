import Foundation

/// Structured result of understanding a freeform income line. Drives the
/// composer's live chips and the eventual `Entry`.
struct ParsedLine: Equatable {
    var amount: Decimal?
    var currencyCode: String = "USD"
    var project: String?
    var task: String = ""
    /// Month-section date from `parseLedgerBlock`; nil means "dated today".
    var date: Date?
    var holdUntil: Date?
    var status: EntryStatus?

    /// Enough information present to commit a real line. A zero amount is not
    /// an income line — it's a note that happened to contain "0".
    var isCommittable: Bool {
        guard let amount, amount > 0 else { return false }
        return !task.isEmpty || project != nil
    }
}
