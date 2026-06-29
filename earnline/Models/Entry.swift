import Foundation
import SwiftData

/// A single income line: "+$240 LunaAI: 2 screens hold until 25.07".
@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var amount: Decimal
    var currencyCode: String
    var project: String?
    var task: String
    var date: Date
    var holdUntil: Date?
    var statusRaw: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date?
    var syncStateRaw: String?
    var lastSyncedAt: Date?

    var client: Client?

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .logged }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(),
         amount: Decimal,
         currencyCode: String = "USD",
         project: String? = nil,
         task: String,
         date: Date = .now,
         holdUntil: Date? = nil,
         status: EntryStatus = .logged,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         syncState: SyncState = .dirty,
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.project = project
        self.task = task
        self.date = date
        self.holdUntil = holdUntil
        self.statusRaw = status.rawValue
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStateRaw = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
    }
}
