import Foundation

/// Typed presentation state keeps mutually exclusive destinations, sheets, and
/// confirmations from drifting into impossible combinations of booleans.
enum LedgerRoute: Hashable {
    case client(UUID)
}

enum LedgerSheetRoute: Identifiable, Equatable {
    case editEntry(UUID)
    case newClient
    case pasteLines
    case insights
    case pending
    case newHeading
    case editHeading(UUID)

    var id: String {
        switch self {
        case .editEntry(let id): "edit-entry-\(id)"
        case .newClient: "new-client"
        case .pasteLines: "paste-lines"
        case .insights: "insights"
        case .pending: "pending"
        case .newHeading: "new-heading"
        case .editHeading(let id): "edit-heading-\(id)"
        }
    }
}

enum LedgerConfirmationRoute: Identifiable, Equatable {
    case deleteEntry(UUID)
    case deleteHeading(UUID)

    var id: String {
        switch self {
        case .deleteEntry(let id): "delete-entry-\(id)"
        case .deleteHeading(let id): "delete-heading-\(id)"
        }
    }
}

struct LedgerComposerRoute: Equatable {
    let clientID: UUID
    let month: Date
}

struct LedgerSearchState {
    /// Drives the system search field docked in the bottom toolbar. True
    /// while the field is expanded (keyboard up, ledger filtering in place).
    var isPresented = false
    var query = ""
    /// Structured filter tokens shown in the field alongside typed text.
    /// They are selected from the native bottom-toolbar Filters menu.
    var tokens: [LedgerSearchToken] = []
}

struct LedgerFeedbackState {
    var impact = 0
    var success = 0
}
