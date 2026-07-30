import Foundation
import SwiftData

enum SyncState: String, Codable {
    case dirty
    case synced
    case failed
}

/// Shared sync surface of the four row models, so the coordinator can mark
/// pushed rows generically.
protocol SyncableModel: PersistentModel {
    var syncUpdatedAt: Date { get }
    var syncState: SyncState { get set }
    var lastSyncedAt: Date? { get set }
    func markSynced(at date: Date)
}

/// The curated SF Symbols that may identify a project. Persisting an enum raw
/// value rather than an arbitrary symbol name keeps synced data renderable on
/// every device; unknown future/invalid values calmly fall back to `folder`.
enum ProjectSymbol: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case folder
    case briefcase
    case display
    case paintpalette
    case camera
    case video
    case music = "music.note"
    case document = "doc.text"
    case megaphone
    case cart
    case globe
    case tools = "wrench.and.screwdriver"
    case package = "shippingbox"
    case sparkles
    case chart = "chart.line.uptrend.xyaxis"
    case building = "building.2"
    case app
    case cloud
    case terminal
    case bolt
    case cpu
    case photo
    case pencil
    case theater
    case creditCard = "creditcard"
    case banknote
    case people = "person.2"
    case calendar
    case storefront
    case bag
    case book = "book.closed"
    case graduationCap = "graduationcap"
    case lightbulb
    case target
    case paintbrush
    case wand = "wand.and.stars"
    case microphone = "mic"
    case headphones
    case keyboard
    case server = "server.rack"
    case network
    case gear = "gearshape"
    case tag
    case receipt
    case phone
    case envelope
    case collaborate = "person.2.wave.2"
    case location = "mappin.and.ellipse"

    var id: String { rawValue }

    /// The default retained for existing ledger rows. New presentation choices
    /// are local display preferences, so the synced raw value stays stable.
    var systemImageName: String {
        systemImageName(for: .fill)
    }

    func systemImageName(for appearance: ProjectIconAppearance) -> String {
        let names = appearance == .outline ? Self.outlineImageNames : Self.filledImageNames
        return names[self] ?? rawValue
    }

    // Keep the wire enum separate from the SF Symbol chosen for each local
    // appearance. Dictionaries make the mapping data rather than a deeply
    // nested branch, which also keeps SwiftLint's complexity signal useful.
    private static let outlineImageNames: [ProjectSymbol: String] = [
        .folder: "folder", .briefcase: "briefcase", .display: "rectangle",
        .paintpalette: "paintpalette", .camera: "camera", .video: "video",
        .music: "music.note", .document: "doc.text", .megaphone: "megaphone",
        .cart: "cart", .globe: "globe.americas", .tools: "wrench.and.screwdriver",
        .package: "shippingbox", .sparkles: "sparkles", .chart: "chart.line.uptrend.xyaxis",
        .building: "building.2", .app: "app", .cloud: "cloud", .terminal: "terminal",
        .bolt: "bolt", .cpu: "cpu", .photo: "photo", .pencil: "pencil.circle",
        .theater: "theatermasks", .creditCard: "creditcard", .banknote: "banknote",
        .people: "person.2", .calendar: "calendar.circle", .storefront: "storefront",
        .bag: "bag", .book: "book.closed", .graduationCap: "graduationcap",
        .lightbulb: "lightbulb", .target: "target", .paintbrush: "paintbrush",
        .wand: "wand.and.stars", .microphone: "mic", .headphones: "headphones",
        .keyboard: "keyboard", .server: "server.rack", .network: "network",
        .gear: "gearshape", .tag: "tag", .receipt: "receipt", .phone: "phone",
        .envelope: "envelope", .collaborate: "person.2.wave.2", .location: "mappin.and.ellipse",
    ]

    private static let filledImageNames: [ProjectSymbol: String] = [
        .folder: "folder.fill", .briefcase: "briefcase.fill", .display: "rectangle.fill",
        .paintpalette: "paintpalette.fill", .camera: "camera.fill", .video: "video.fill",
        .music: "music.note", .document: "doc.fill", .megaphone: "megaphone.fill",
        .cart: "cart.fill", .globe: "globe.americas.fill", .tools: "wrench.and.screwdriver.fill",
        .package: "shippingbox.fill", .sparkles: "sparkles", .chart: "chart.bar.fill",
        .building: "building.2.fill", .app: "app.fill", .cloud: "cloud.fill",
        .terminal: "terminal.fill", .bolt: "bolt.fill", .cpu: "cpu.fill",
        .photo: "photo.fill", .pencil: "pencil.circle.fill", .theater: "theatermasks.fill",
        .creditCard: "creditcard.fill", .banknote: "banknote.fill", .people: "person.2.fill",
        .calendar: "calendar.circle.fill", .storefront: "storefront.fill", .bag: "bag.fill",
        .book: "book.closed.fill", .graduationCap: "graduationcap.fill",
        .lightbulb: "lightbulb.fill", .target: "target", .paintbrush: "paintbrush.fill",
        .wand: "wand.and.stars", .microphone: "mic.fill", .headphones: "headphones",
        .keyboard: "keyboard.fill", .server: "server.rack", .network: "network",
        .gear: "gearshape.fill", .tag: "tag.fill", .receipt: "doc.text.fill",
        .phone: "phone.fill", .envelope: "envelope.fill", .collaborate: "person.2.fill",
        .location: "mappin.circle.fill",
    ]

    static func resolved(_ rawValue: String?) -> ProjectSymbol {
        rawValue.flatMap(ProjectSymbol.init(rawValue:)) ?? .folder
    }
}

/// Presentation is deliberately local to a device. A project keeps the same
/// semantic symbol in synced data while each person can choose the calmer
/// outline treatment or the more emphatic filled one for their ledger.
enum ProjectIconAppearance: String, CaseIterable, Identifiable, Sendable {
    case outline
    case fill

    static let userDefaultsKey = "projectIconAppearance"

    var id: String { rawValue }
}

/// Stable identity shared by every place that reads or writes a free-form
/// `Entry.project`. Whitespace, case, width, and diacritics do not create
/// duplicate icon preferences for the same human-readable project name.
enum ProjectIconResolver {
    nonisolated static func normalizedKey(for projectName: String) -> String {
        projectName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    nonisolated static func preferenceID(for projectName: String) -> UUID? {
        let key = normalizedKey(for: projectName)
        guard !key.isEmpty else { return nil }
        return DeterministicID.uuid("earnline-project-icon:\(key)")
    }

    nonisolated static func symbolsByProjectKey(
        _ preferences: [ProjectIconPreference]
    ) -> [String: ProjectSymbol] {
        Dictionary(preferences.map { ($0.projectKey, $0.symbol) },
                   uniquingKeysWith: { _, latest in latest })
    }

    nonisolated static func symbol(
        for projectName: String,
        in preferences: [ProjectIconPreference]
    ) -> ProjectSymbol {
        let key = normalizedKey(for: projectName)
        return preferences.first { $0.projectKey == key }?.symbol ?? .folder
    }
}

/// One workspace-wide icon override for a normalized project name. Projects
/// remain free-form strings on `Entry`; this compact metadata row avoids
/// rewriting every historical entry when a user changes one icon.
@Model
final class ProjectIconPreference {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var projectKey: String
    var symbolNameRaw: String
    var createdAt: Date
    var updatedAt: Date?
    var syncStateRaw: String?
    var lastSyncedAt: Date?

    var symbol: ProjectSymbol {
        get { ProjectSymbol.resolved(symbolNameRaw) }
        set { symbolNameRaw = newValue.rawValue }
    }

    init(id: UUID,
         projectKey: String,
         symbol: ProjectSymbol = .folder,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         syncState: SyncState = .dirty,
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.projectKey = projectKey
        self.symbolNameRaw = symbol.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStateRaw = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
    }
}

enum ProjectIconPreferenceError: LocalizedError, Equatable {
    case emptyProjectName

    var errorDescription: String? {
        switch self {
        case .emptyProjectName:
            return "A project name is required before choosing an icon."
        }
    }
}

/// Mutation boundary for Settings/UI integration. This intentionally does not
/// save the context: callers use `LedgerMutationStore.save(_:)` so failure and sync queueing
/// follow the same visible contract as every other Earnline edit.
@MainActor
enum ProjectIconPreferenceStore {
    static func preference(
        for projectName: String,
        in context: ModelContext
    ) throws -> ProjectIconPreference? {
        let projectKey = ProjectIconResolver.normalizedKey(for: projectName)
        guard !projectKey.isEmpty else {
            throw ProjectIconPreferenceError.emptyProjectName
        }
        return try context.fetch(FetchDescriptor<ProjectIconPreference>(
            predicate: #Predicate { $0.projectKey == projectKey }
        )).first
    }

    @discardableResult
    static func set(
        _ symbol: ProjectSymbol,
        for projectName: String,
        in context: ModelContext
    ) throws -> ProjectIconPreference {
        let projectKey = ProjectIconResolver.normalizedKey(for: projectName)
        guard let id = ProjectIconResolver.preferenceID(for: projectName) else {
            throw ProjectIconPreferenceError.emptyProjectName
        }
        if let existing = try context.fetch(FetchDescriptor<ProjectIconPreference>(
            predicate: #Predicate { $0.projectKey == projectKey }
        )).first {
            guard existing.symbol != symbol else { return existing }
            existing.symbol = symbol
            existing.markDirty()
            return existing
        }
        let preference = ProjectIconPreference(id: id, projectKey: projectKey, symbol: symbol)
        context.insert(preference)
        return preference
    }
}

/// Versioned schema so future model changes ship with an explicit migration
/// path instead of a crash-on-launch for existing synced stores.
enum EarnlineSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Client.self, Entry.self, Heading.self, SyncTombstone.self]
    }
}

enum EarnlineSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Client.self, Entry.self, Heading.self, SyncTombstone.self, ProjectIconPreference.self]
    }
}

enum EarnlineSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Client.self, Entry.self, Heading.self, SyncTombstone.self, ProjectIconPreference.self, MonthReview.self]
    }
}

enum EarnlineMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EarnlineSchemaV1.self, EarnlineSchemaV2.self, EarnlineSchemaV3.self]
    }
    static var stages: [MigrationStage] { [v1toV2, v2toV3] }

    static let v1toV2 = MigrationStage.lightweight(
        fromVersion: EarnlineSchemaV1.self,
        toVersion: EarnlineSchemaV2.self
    )

    static let v2toV3 = MigrationStage.lightweight(
        fromVersion: EarnlineSchemaV2.self,
        toVersion: EarnlineSchemaV3.self
    )
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
extension ProjectIconPreference: SyncableModel {}
extension MonthReview: SyncableModel {}

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

extension ProjectIconPreference {
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

extension MonthReview {
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
    static func dequeue(_ entity: SyncEntity, id recordID: UUID, in context: ModelContext) throws {
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
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
