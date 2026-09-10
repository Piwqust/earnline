import Foundation

enum LedgerImportFile {
    static let maximumBytes = 20 * 1_024 * 1_024

    enum ReadError: LocalizedError {
        case tooLarge
        case unreadable
        var errorDescription: String? {
            switch self {
            case .tooLarge: String(localized: "This file exceeds the 20 MB import limit.")
            case .unreadable: String(localized: "This file could not be read.")
            }
        }
    }

    /// Bound the actual read as well as the metadata check: a file provider
    /// can change its size between selection and reading.
    static func read(_ url: URL) throws -> Data {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            throw ReadError.tooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw ReadError.tooLarge }
        return data
    }

    @concurrent
    static func readInBackground(_ url: URL) async throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        return try read(url)
    }
}
