import Foundation
import SwiftData

enum SyncState: String, Codable {
    case dirty
    case synced
    case failed
}

/// Shared sync surface of the three row models, so the coordinator can mark
/// pushed rows generically.
protocol SyncableModel: PersistentModel {
    var syncUpdatedAt: Date { get }
    var syncState: SyncState { get set }
    var lastSyncedAt: Date? { get set }
    func markSynced(at date: Date)
}

/// Versioned schema so future model changes ship with an explicit migration
/// path instead of a crash-on-launch for existing synced stores.
enum EarnlineSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Client.self, Entry.self, Heading.self, SyncTombstone.self]
    }
}

enum EarnlineMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [EarnlineSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
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

extension Client: SyncableModel {}
extension Entry: SyncableModel {}
extension Heading: SyncableModel {}

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
        context.insert(SyncTombstone(id: tombstoneID(entity, recordID: recordID),
                                     entity: entity,
                                     recordID: recordID))
    }

    /// Remove a still-local tombstone — used by undo, so a restored row isn't
    /// chased by its own queued delete. Scans in memory (the table holds only
    /// deletes awaiting the next sync): predicating on a custom `id` property
    /// trips over `Identifiable.id` at runtime.
    static func dequeue(_ entity: SyncEntity, id recordID: UUID, in context: ModelContext) {
        let tombstones = (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? []
        tombstones
            .filter { $0.recordID == recordID && $0.entity == entity }
            .forEach(context.delete)
    }

    /// Deterministic per-row id: enqueueing the same delete twice stays one
    /// tombstone.
    private static func tombstoneID(_ entity: SyncEntity, recordID: UUID) -> UUID {
        DeterministicID.uuid("tombstone:\(entity.rawValue):\(recordID.uuidString)")
    }
}
