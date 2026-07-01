import SwiftUI

/// The state of an income line. Most lines the user adds are *already paid*, so
/// `paid` is the calm, unremarkable default (gray). Lines that still need work
/// (`inProgress`, orange) or fell through (`canceled`, red) stand out instead.
enum EntryStatus: String, Codable, CaseIterable, Identifiable {
    case paid
    case inProgress
    case canceled

    static func fromSyncRawValue(_ rawValue: String) -> EntryStatus {
        switch rawValue {
        case "logged":
            return .paid
        default:
            return EntryStatus(rawValue: rawValue) ?? .paid
        }
    }

    var id: String { rawValue }

    var isIncludedInEarnedTotals: Bool {
        self != .canceled
    }

    var title: String {
        switch self {
        case .paid: return String(localized: "Paid")
        case .inProgress: return String(localized: "In progress")
        case .canceled: return String(localized: "Canceled")
        }
    }

    /// SF Symbol drawn as the trailing status dot.
    var symbol: String {
        switch self {
        case .paid: return "checkmark.circle.fill"
        case .inProgress: return "clock.fill"
        case .canceled: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .paid: return Theme.statusPaid          // gray — unremarkable
        case .inProgress: return Theme.statusProgress // orange
        case .canceled: return Theme.statusCanceled   // red
        }
    }

    /// Order used when cycling: paid → in progress → canceled → paid.
    var next: EntryStatus {
        switch self {
        case .paid: return .inProgress
        case .inProgress: return .canceled
        case .canceled: return .paid
        }
    }
}
