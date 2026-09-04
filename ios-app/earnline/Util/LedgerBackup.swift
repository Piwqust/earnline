import Foundation
import SwiftData

enum LedgerBackupError: LocalizedError, Equatable {
    case invalidFormat
    case unsupportedVersion(Int)
    case duplicateRecord(String)
    case missingClient(UUID)
    case orphanedEntry(UUID)
    case invalidAmount(UUID)
    case unsupportedCurrency(String)
    case invalidProjectIcon(String)
    case invalidMonthReview(UUID)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return String(localized: "This file is not a valid Earnline backup.")
        case .unsupportedVersion(let version):
            return String(localized: "This Earnline backup uses an unsupported format version: \(version).")
        case .duplicateRecord(let kind):
            return String(localized: "This backup contains duplicate \(kind) records.")
        case .missingClient(let id):
            return String(localized: "This backup refers to a missing client (\(id.uuidString)).")
        case .orphanedEntry(let id):
            return String(localized: "Income line \(id.uuidString) has no client.")
        case .invalidAmount(let id):
            return String(localized: "Income line \(id.uuidString) has an invalid amount.")
        case .unsupportedCurrency(let code):
            return String(localized: "This backup contains an unsupported currency: \(code).")
        case .invalidProjectIcon(let key):
            return String(localized: "This backup contains an invalid project icon: \(key).")
        case .invalidMonthReview(let id):
            return String(localized: "Month review \(id.uuidString) is invalid.")
        }
    }
}

/// A portable, user-controlled copy of the local workspace. Sync tombstones
/// and server cursors are intentionally excluded: restoring a file must add
/// user data to the current workspace, never replay an old delete into it.
struct LedgerBackup: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct Settings: Codable, Equatable, Sendable {
        let baseCurrencyCode: String
        let secondaryCurrencyCode: String
        let exchangeRate: String
    }

    struct ClientRecord: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let colorHex: String
        let sortIndex: Int
        let createdAt: Date
        let updatedAt: Date?
    }

    struct EntryRecord: Codable, Equatable, Sendable {
        let id: UUID
        let clientID: UUID
        let amount: String
        let currencyCode: String
        let project: String?
        let task: String
        let date: Date
        let holdUntil: Date?
        let status: EntryStatus
        let sortIndex: Int
        let createdAt: Date
        let updatedAt: Date?
    }

    struct HeadingRecord: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let date: Date
        let sortIndex: Int
        let createdAt: Date
        let updatedAt: Date?
    }

    struct ProjectIconRecord: Codable, Equatable, Sendable {
        let id: UUID
        let projectKey: String
        let symbol: ProjectSymbol
        let createdAt: Date
        let updatedAt: Date?
    }

    struct MonthReviewRecord: Codable, Equatable, Sendable {
        let id: UUID
        let monthStart: Date
        let note: String
        let closedAt: Date?
        let createdAt: Date
        let updatedAt: Date?
    }

    let formatVersion: Int
    let exportedAt: Date
    let workspaceID: String
    let settings: Settings
    let clients: [ClientRecord]
    let entries: [EntryRecord]
    let headings: [HeadingRecord]
    let projectIcons: [ProjectIconRecord]
    let monthReviews: [MonthReviewRecord]

    struct ImportSummary: Equatable, Sendable {
        var clients = 0
        var entries = 0
        var headings = 0
        var projectIcons = 0
        var monthReviews = 0
        var skippedExisting = 0

        var inserted: Int {
            clients + entries + headings + projectIcons + monthReviews
        }
    }

    var totalRecords: Int {
        clients.count + entries.count + headings.count + projectIcons.count + monthReviews.count
    }

    func validated() throws -> LedgerBackup {
        guard formatVersion == Self.currentVersion else {
            throw LedgerBackupError.unsupportedVersion(formatVersion)
        }
        guard !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LedgerBackupError.invalidFormat
        }
        guard Limits.supportedCurrencyCodes.contains(settings.baseCurrencyCode),
              Limits.supportedCurrencyCodes.contains(settings.secondaryCurrencyCode),
              settings.baseCurrencyCode != settings.secondaryCurrencyCode,
              let rate = Decimal(string: settings.exchangeRate, locale: Self.locale),
              rate > 0 else {
            throw LedgerBackupError.invalidFormat
        }

        try ensureUnique(clients.map(\.id), kind: "client")
        try ensureUnique(entries.map(\.id), kind: "income line")
        try ensureUnique(headings.map(\.id), kind: "heading")
        try ensureUnique(projectIcons.map(\.id), kind: "project icon")
        try ensureUnique(monthReviews.map(\.id), kind: "month review")

        try validateClients()
        try validateEntries(clientIDs: Set(clients.map(\.id)))
        try validateHeadings()
        try validateProjectIcons()
        try validateMonthReviews()
        return self
    }

    private static let locale = Locale(identifier: "en_US_POSIX")

    private func ensureUnique(_ ids: [UUID], kind: String) throws {
        guard Set(ids).count == ids.count else {
            throw LedgerBackupError.duplicateRecord(kind)
        }
    }

    private func validateClients() throws {
        for client in clients where !SyncValidation.isValidClient(name: client.name, colorHex: client.colorHex) {
            throw LedgerBackupError.invalidFormat
        }
    }

    private func validateEntries(clientIDs: Set<UUID>) throws {
        for entry in entries {
            guard clientIDs.contains(entry.clientID) else {
                throw LedgerBackupError.missingClient(entry.clientID)
            }
            guard let amount = Decimal(string: entry.amount, locale: Self.locale),
                  amount > 0,
                  amount.rounded(2) == amount else {
                throw LedgerBackupError.invalidAmount(entry.id)
            }
            guard Limits.supportedCurrencyCodes.contains(entry.currencyCode) else {
                throw LedgerBackupError.unsupportedCurrency(entry.currencyCode)
            }
            guard SyncValidation.isValidEntry(
                amount: amount,
                currencyCode: entry.currencyCode,
                project: entry.project,
                task: entry.task,
                status: entry.status.rawValue
            ) else {
                throw LedgerBackupError.invalidFormat
            }
        }
    }

    private func validateHeadings() throws {
        for heading in headings where !SyncValidation.isValidHeading(title: heading.title) {
            throw LedgerBackupError.invalidFormat
        }
    }

    private func validateProjectIcons() throws {
        var iconKeys = Set<String>()
        for icon in projectIcons {
            guard !icon.projectKey.isEmpty,
                  ProjectSymbol(rawValue: icon.symbol.rawValue) != nil,
                  iconKeys.insert(icon.projectKey).inserted else {
                throw LedgerBackupError.invalidProjectIcon(icon.projectKey)
            }
        }
    }

    private func validateMonthReviews() throws {
        var reviewMonths = Set<String>()
        for review in monthReviews {
            let canonicalStart = MonthReview.monthStart(of: review.monthStart)
            let monthKey = SyncDateCodec.dayString(canonicalStart)
            guard MonthReview.isValid(note: review.note),
                  review.id == MonthReview.id(for: canonicalStart),
                  reviewMonths.insert(monthKey).inserted else {
                throw LedgerBackupError.invalidMonthReview(review.id)
            }
        }
    }
}

@MainActor
enum LedgerBackupCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode(_ backup: LedgerBackup) throws -> Data {
        try encoder.encode(backup.validated())
    }

    static func decode(_ data: Data) throws -> LedgerBackup {
        do {
            return try decoder.decode(LedgerBackup.self, from: data).validated()
        } catch let error as LedgerBackupError {
            throw error
        } catch {
            throw LedgerBackupError.invalidFormat
        }
    }

    static func export(context: ModelContext, app: AppModel) throws -> Data {
        let clients = try context.fetch(FetchDescriptor<Client>()).filter { !$0.isInvalidated }
        let entries = try context.fetch(FetchDescriptor<Entry>()).filter { !$0.isInvalidated }
        let headings = try context.fetch(FetchDescriptor<Heading>()).filter { !$0.isInvalidated }
        let icons = try context.fetch(FetchDescriptor<ProjectIconPreference>()).filter { !$0.isInvalidated }
        let reviews = try context.fetch(FetchDescriptor<MonthReview>()).filter { !$0.isInvalidated }
        let clientIDs = Set(clients.map(\.id))

        var entryRecords: [LedgerBackup.EntryRecord] = []
        entryRecords.reserveCapacity(entries.count)
        for entry in entries {
            guard let clientID = entry.client?.id else {
                throw LedgerBackupError.orphanedEntry(entry.id)
            }
            guard clientIDs.contains(clientID) else {
                throw LedgerBackupError.missingClient(clientID)
            }
            entryRecords.append(.init(
                id: entry.id,
                clientID: clientID,
                amount: NSDecimalNumber(decimal: entry.amount).stringValue,
                currencyCode: entry.currencyCode,
                project: entry.project,
                task: entry.task,
                date: entry.date,
                holdUntil: entry.holdUntil,
                status: entry.status,
                sortIndex: entry.sortIndex,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            ))
        }

        let backup = LedgerBackup(
            formatVersion: LedgerBackup.currentVersion,
            exportedAt: .now,
            workspaceID: app.workspaceID,
            settings: .init(
                baseCurrencyCode: app.baseCurrencyCode,
                secondaryCurrencyCode: app.secondaryCurrencyCode,
                exchangeRate: NSDecimalNumber(value: app.rate).stringValue
            ),
            clients: clients.map {
                .init(id: $0.id, name: $0.name, colorHex: $0.colorHex,
                      sortIndex: $0.sortIndex, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            entries: entryRecords,
            headings: headings.map {
                .init(id: $0.id, title: $0.title, date: $0.date,
                      sortIndex: $0.sortIndex, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            projectIcons: icons.map {
                .init(id: $0.id, projectKey: $0.projectKey, symbol: $0.symbol,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            monthReviews: reviews.map {
                .init(id: $0.id, monthStart: $0.monthStart, note: $0.note,
                      closedAt: $0.closedAt, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }
        )
        return try encode(backup)
    }

    /// Inserts only records whose ids are absent from the current store. The
    /// caller owns the final save, so a failed transaction can roll back all
    /// inserted records through `LedgerMutationStore`.
    @discardableResult
    static func importBackup(_ backup: LedgerBackup, into context: ModelContext) throws -> LedgerBackup.ImportSummary {
        let backup = try backup.validated()
        let existingClients = try context.fetch(FetchDescriptor<Client>())
        let existingEntries = try context.fetch(FetchDescriptor<Entry>())
        let existingHeadings = try context.fetch(FetchDescriptor<Heading>())
        let existingIcons = try context.fetch(FetchDescriptor<ProjectIconPreference>())
        let existingReviews = try context.fetch(FetchDescriptor<MonthReview>())

        var summary = LedgerBackup.ImportSummary()
        var clientsByID = Dictionary(uniqueKeysWithValues: existingClients.map { ($0.id, $0) })
        let existingEntryIDs = Set(existingEntries.map(\.id))
        let existingHeadingIDs = Set(existingHeadings.map(\.id))
        let existingIconIDs = Set(existingIcons.map(\.id))
        let existingIconKeys = Set(existingIcons.map(\.projectKey))
        let existingReviewIDs = Set(existingReviews.map(\.id))
        let now = Date.now

        for record in backup.clients where clientsByID[record.id] == nil {
            let client = Client(id: record.id, name: record.name, colorHex: record.colorHex,
                                sortIndex: record.sortIndex, createdAt: record.createdAt,
                                updatedAt: now, syncState: .dirty)
            context.insert(client)
            clientsByID[record.id] = client
            summary.clients += 1
        }

        for record in backup.entries where !existingEntryIDs.contains(record.id) {
            guard let client = clientsByID[record.clientID],
                  let amount = Decimal(string: record.amount, locale: Locale(identifier: "en_US_POSIX")) else {
                throw LedgerBackupError.missingClient(record.clientID)
            }
            let entry = Entry(id: record.id, amount: amount, currencyCode: record.currencyCode,
                              project: record.project, task: record.task, date: record.date,
                              holdUntil: record.holdUntil, status: record.status,
                              sortIndex: record.sortIndex, createdAt: record.createdAt,
                              updatedAt: now, syncState: .dirty)
            entry.client = client
            context.insert(entry)
            summary.entries += 1
        }

        for record in backup.headings where !existingHeadingIDs.contains(record.id) {
            context.insert(Heading(id: record.id, title: record.title, date: record.date,
                                   sortIndex: record.sortIndex, createdAt: record.createdAt,
                                   updatedAt: now, syncState: .dirty))
            summary.headings += 1
        }

        for record in backup.projectIcons
        where !existingIconIDs.contains(record.id) && !existingIconKeys.contains(record.projectKey) {
            context.insert(ProjectIconPreference(id: record.id, projectKey: record.projectKey,
                                                 symbol: record.symbol, createdAt: record.createdAt,
                                                 updatedAt: now, syncState: .dirty))
            summary.projectIcons += 1
        }

        for record in backup.monthReviews where !existingReviewIDs.contains(record.id) {
            context.insert(MonthReview(id: record.id, monthStart: record.monthStart,
                                       note: record.note, closedAt: record.closedAt,
                                       createdAt: record.createdAt, updatedAt: now,
                                       syncState: .dirty))
            summary.monthReviews += 1
        }

        summary.skippedExisting = backup.totalRecords - summary.inserted
        return summary
    }
}
