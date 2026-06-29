import Foundation
import SwiftData

enum SyncState: String, Codable {
    case dirty
    case synced
    case failed
}

enum SyncEntity: String, Codable, CaseIterable {
    case client
    case entry
    case heading
}

@Model
final class SyncTombstone {
    @Attribute(.unique) var id: UUID
    var entityRaw: String
    var recordID: UUID
    var deletedAt: Date
    var createdAt: Date

    var entity: SyncEntity {
        get { SyncEntity(rawValue: entityRaw) ?? .entry }
        set { entityRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(),
         entity: SyncEntity,
         recordID: UUID,
         deletedAt: Date = .now,
         createdAt: Date = .now) {
        self.id = id
        self.entityRaw = entity.rawValue
        self.recordID = recordID
        self.deletedAt = deletedAt
        self.createdAt = createdAt
    }
}

extension Client {
    var syncState: SyncState {
        get { syncStateRaw.flatMap(SyncState.init(rawValue:)) ?? .dirty }
        set { syncStateRaw = newValue.rawValue }
    }

    var needsSync: Bool { syncState != .synced }
    var syncUpdatedAt: Date { updatedAt ?? createdAt }

    func markDirty(at date: Date = .now) {
        updatedAt = date
        syncState = .dirty
    }

    func markSynced(at date: Date = .now) {
        syncState = .synced
        lastSyncedAt = date
    }
}

extension Entry {
    var syncState: SyncState {
        get { syncStateRaw.flatMap(SyncState.init(rawValue:)) ?? .dirty }
        set { syncStateRaw = newValue.rawValue }
    }

    var needsSync: Bool { syncState != .synced }
    var syncUpdatedAt: Date { updatedAt ?? createdAt }

    func markDirty(at date: Date = .now) {
        updatedAt = date
        syncState = .dirty
    }

    func markSynced(at date: Date = .now) {
        syncState = .synced
        lastSyncedAt = date
    }
}

extension Heading {
    var syncState: SyncState {
        get { syncStateRaw.flatMap(SyncState.init(rawValue:)) ?? .dirty }
        set { syncStateRaw = newValue.rawValue }
    }

    var needsSync: Bool { syncState != .synced }
    var syncUpdatedAt: Date { updatedAt ?? createdAt }

    func markDirty(at date: Date = .now) {
        updatedAt = date
        syncState = .dirty
    }

    func markSynced(at date: Date = .now) {
        syncState = .synced
        lastSyncedAt = date
    }
}

enum SyncDeleteQueue {
    static func enqueue(_ entity: SyncEntity, id recordID: UUID, in context: ModelContext) {
        context.insert(SyncTombstone(id: DeterministicID.uuid("tombstone:\(entity.rawValue):\(recordID.uuidString)"),
                                     entity: entity,
                                     recordID: recordID))
    }
}
