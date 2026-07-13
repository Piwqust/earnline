import SwiftUI

enum LedgerRow: Identifiable {
    /// Month and client rows carry their earned total, computed once in the
    /// snapshot pass — a row must never re-derive it by walking entries.
    case month(Date, Decimal)
    case heading(Heading)
    case client(Client, Date, Decimal)
    case composer(Client)
    case entry(Entry)

    var id: String {
        switch self {
        case .month(let date, _): "m-\(date.timeIntervalSinceReferenceDate)"
        case .heading(let heading): "h-\(heading.id)"
        case .client(let client, let date, _): "c-\(client.id)-\(date.timeIntervalSinceReferenceDate)"
        case .composer(let client): "composer-\(client.id)"
        case .entry(let entry): "e-\(entry.id)"
        }
    }

    /// A sync pull can invalidate a model while a recycled List row still
    /// exists. Registration metadata remains safe to inspect in that window.
    var isInvalidated: Bool {
        switch self {
        case .month: false
        case .heading(let heading): heading.isInvalidated
        case .client(let client, _, _): client.isInvalidated
        case .composer(let client): client.isInvalidated
        case .entry(let entry): entry.isInvalidated
        }
    }
}

enum LedgerBlock: Identifiable {
    case heading(Heading)
    case client(Client)

    var id: String {
        switch self {
        case .heading(let heading): "h-\(heading.id)"
        case .client(let client): "c-\(client.id)"
        }
    }

    var sortIndex: Int {
        switch self {
        case .heading(let heading): heading.sortIndex
        case .client(let client): client.sortIndex
        }
    }

    private var createdAt: Date {
        switch self {
        case .heading(let heading): heading.createdAt
        case .client(let client): client.createdAt
        }
    }

    func applySortIndex(_ index: Int) {
        switch self {
        case .heading(let heading):
            heading.sortIndex = index
            heading.markDirty()
        case .client(let client):
            client.sortIndex = index
            client.markDirty()
        }
    }

    func isOrderedBefore(_ other: LedgerBlock) -> Bool {
        sortIndex == other.sortIndex ? createdAt < other.createdAt : sortIndex < other.sortIndex
    }
}

struct MonthAnchor: Equatable {
    let month: Date
    let y: CGFloat
}

struct MonthAnchorKey: PreferenceKey {
    static let defaultValue: [MonthAnchor] = []

    static func reduce(value: inout [MonthAnchor], nextValue: () -> [MonthAnchor]) {
        value.append(contentsOf: nextValue())
    }
}
