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
    /// Whether a search session is running — i.e. whether the `.searchable`
    /// modifier is attached at all. The ledger has no resting search field;
    /// the modifier exists only between `startSearch()` and `endSearch()`.
    var isActive = false
    /// Drives the system field's presentation once the modifier is mounted.
    var isPresented = false
    var query = ""
}

struct LedgerFeedbackState {
    var impact = 0
    var success = 0
}
