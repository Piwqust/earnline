import SwiftUI

/// The lifecycle of an income line. Three calm states mirroring the
/// user's notebook markers: plain (+), ⌛ hold/in-progress, ✅ paid.
enum EntryStatus: String, Codable, CaseIterable, Identifiable {
    case logged
    case inProgress
    case paid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logged: return "Logged"
        case .inProgress: return "In progress"
        case .paid: return "Paid"
        }
    }

    /// SF Symbol drawn as the trailing status dot.
    var symbol: String {
        switch self {
        case .logged: return "circle"
        case .inProgress: return "circle.righthalf.filled"
        case .paid: return "circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .logged: return Theme.statusLogged
        case .inProgress: return Theme.statusProgress
        case .paid: return Theme.statusPaid
        }
    }

    /// Order used when cycling on tap: logged → inProgress → paid → logged.
    var next: EntryStatus {
        switch self {
        case .logged: return .inProgress
        case .inProgress: return .paid
        case .paid: return .logged
        }
    }
}
