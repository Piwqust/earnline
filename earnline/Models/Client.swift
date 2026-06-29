import Foundation
import SwiftData

/// A payer the income is grouped under — rendered as a colored chip.
@Model
final class Client {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date?
    var syncStateRaw: String?
    var lastSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Entry.client)
    var entries: [Entry] = []

    init(id: UUID = UUID(),
         name: String,
         colorHex: String = Theme.blue.hexString,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         syncState: SyncState = .dirty,
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStateRaw = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
    }
}
