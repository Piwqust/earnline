import Foundation
import SwiftData

enum LedgerSafetySnapshotError: LocalizedError, Equatable {
    case unreadableSnapshot

    var errorDescription: String? {
        switch self {
        case .unreadableSnapshot:
            return String(localized: "This safety snapshot could not be read. The file was left in place.")
        }
    }
}

/// Automatic local copies written right before Earnline empties a local store
/// (“Use cloud copy”, “Reset and pull”). They reuse the versioned JSON backup
/// format, live in Application Support per workspace store, and only the newest
/// few are kept. Restoring one is the same merge-only import as a manual backup.
@MainActor
enum LedgerSafetySnapshots {
    static let retainedCount = 5

    enum Reason: String, CaseIterable {
        case resetAndPull = "reset-and-pull"
        case useCloudCopy = "use-cloud-copy"

        var title: String {
            switch self {
            case .resetAndPull: String(localized: "Before reset and pull")
            case .useCloudCopy: String(localized: "Before using the cloud copy")
            }
        }
    }

    struct Snapshot: Identifiable, Equatable, Hashable {
        let url: URL
        let createdAt: Date
        let reason: Reason?
        let fileSize: Int

        var id: URL { url }

        var title: String {
            reason?.title ?? String(localized: "Safety snapshot")
        }
    }

    private static let fileExtension = "json"

    /// One directory per local store, so a Test snapshot can never be mistaken
    /// for a Production one and a signed-out cache stays apart from an account.
    static func directory(forStoreIdentity identity: String,
                          fileManager: FileManager = .default) throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: true)
        let folder = root
            .appendingPathComponent("earnline", isDirectory: true)
            .appendingPathComponent("safety-snapshots", isDirectory: true)
            .appendingPathComponent(safeDirectoryName(identity), isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a snapshot of the current store. Returns nil when there is
    /// nothing to protect, so an empty cache never produces an empty file.
    @discardableResult
    static func capture(context: ModelContext,
                        app: AppModel,
                        reason: Reason,
                        now: Date = .now,
                        fileManager: FileManager = .default) throws -> Snapshot? {
        let data = try LedgerBackupCodec.export(context: context, app: app)
        guard data.count <= LedgerImportFile.maximumBytes else { throw LedgerImportFile.ReadError.tooLarge }
        let backup = try LedgerBackupCodec.decode(data)
        guard backup.totalRecords > 0 else { return nil }

        let folder = try directory(forStoreIdentity: app.workspaceStoreIdentity, fileManager: fileManager)
        let url = folder.appendingPathComponent(fileName(for: reason, at: now) + "_" + UUID().uuidString)
            .appendingPathExtension(fileExtension)
        // Financial data at rest: complete protection is safe because snapshots
        // are only ever written and read while the app is in the foreground.
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try prune(storeIdentity: app.workspaceStoreIdentity, fileManager: fileManager)
        return Snapshot(url: url, createdAt: now, reason: reason, fileSize: data.count)
    }

    /// Newest first.
    static func list(forStoreIdentity identity: String,
                     fileManager: FileManager = .default) throws -> [Snapshot] {
        let folder = try directory(forStoreIdentity: identity, fileManager: fileManager)
        let urls = try fileManager.contentsOfDirectory(at: folder,
                                                       includingPropertiesForKeys: [.fileSizeKey],
                                                       options: [.skipsHiddenFiles])
        return urls
            .filter { $0.pathExtension == fileExtension }
            .compactMap { url -> Snapshot? in
                guard let parsed = parseFileName(url.deletingPathExtension().lastPathComponent) else { return nil }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return Snapshot(url: url, createdAt: parsed.createdAt, reason: parsed.reason, fileSize: size)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func load(_ snapshot: Snapshot) throws -> LedgerBackup {
        let data: Data
        do {
            data = try LedgerImportFile.read(snapshot.url)
        } catch {
            throw LedgerSafetySnapshotError.unreadableSnapshot
        }
        return try LedgerBackupCodec.decode(data)
    }

    static func delete(_ snapshot: Snapshot, fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: snapshot.url)
    }

    /// Keeps the newest `retainedCount` snapshots of one store.
    static func prune(storeIdentity identity: String,
                      keeping count: Int = retainedCount,
                      fileManager: FileManager = .default) throws {
        let snapshots = try list(forStoreIdentity: identity, fileManager: fileManager)
        for stale in snapshots.dropFirst(max(count, 0)) {
            try fileManager.removeItem(at: stale.url)
        }
    }

    // MARK: File names

    /// `2026-09-10T21-05-33Z-use-cloud-copy`: sortable, filesystem-safe, and
    /// self-describing without a sidecar index that could drift from disk.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter
    }()

    static func fileName(for reason: Reason, at date: Date) -> String {
        "\(stampFormatter.string(from: date))-\(reason.rawValue)"
    }

    static func parseFileName(_ name: String) -> (createdAt: Date, reason: Reason?)? {
        // The stamp is a fixed 20 characters; whatever follows the dash is the reason.
        guard name.count > 21 else { return nil }
        let stampEnd = name.index(name.startIndex, offsetBy: 20)
        guard let createdAt = stampFormatter.date(from: String(name[..<stampEnd])),
              name[stampEnd] == "-" else { return nil }
        let reasonText = name[name.index(after: stampEnd)...].split(separator: "_").first.map(String.init) ?? ""
        let reason = Reason(rawValue: reasonText)
        return (createdAt, reason)
    }

    static func safeDirectoryName(_ identity: String) -> String {
        let mapped = identity.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let name = String(mapped)
        return name.isEmpty ? "default" : name
    }
}
