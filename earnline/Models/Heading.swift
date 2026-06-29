import Foundation
import SwiftData

/// A free-text divider the user can drop between sections ("New Heading").
@Model
final class Heading {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date?
    var syncStateRaw: String?
    var lastSyncedAt: Date?

    init(id: UUID = UUID(),
         title: String,
         date: Date = .now,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         syncState: SyncState = .dirty,
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStateRaw = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
    }
}
