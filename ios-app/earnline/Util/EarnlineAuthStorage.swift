import CryptoKit
import Foundation
import Security
import Supabase

/// Project-scoped Keychain storage for Supabase sessions. The SDK's default
/// adapter shares one generic service and swallows several Keychain failures;
/// this adapter makes access policy, migration, and failures explicit.
final class EarnlineAuthStorage: AuthLocalStorage, @unchecked Sendable {
    enum StorageError: LocalizedError {
        case keychain(OSStatus)
        case unreadableData

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                // swiftlint:disable:next line_length
                return String(localized: "Secure sign-in storage could not be updated (Keychain status \(status)). Unlock this iPhone and try again.")
            case .unreadableData:
                return String(localized: "Secure sign-in storage returned unreadable data.")
            }
        }
    }

    let sessionKey: String
    private let service: String
    private let legacySessionKey: String
    private let lock = NSLock()

    init(projectURL: URL) {
        let projectReference = (projectURL.host ?? "default")
            .split(separator: ".")
            .first
            .map(String.init) ?? "default"
        service = "com.earnline.auth.\(projectReference)"
        sessionKey = "earnline.session.v1"
        legacySessionKey = "sb-\(projectReference)-auth-token"
    }

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(value, service: service, account: key)
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return try read(service: service, account: key)
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try delete(service: service, account: key)
    }

    /// Moves the previous SDK-default entry into the project-scoped service on
    /// first use. The old entry is removed only after the new one is written.
    func migrateLegacySessionIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        guard try read(service: service, account: sessionKey) == nil,
              let legacy = try read(service: "supabase.gotrue.swift", account: legacySessionKey)
        else { return }
        try write(legacy, service: service, account: sessionKey)
        try delete(service: "supabase.gotrue.swift", account: legacySessionKey)
    }

    func removeSession() throws {
        try remove(key: sessionKey)
    }

    /// A durable request id lets a pairing retry retrieve the session produced
    /// by its original request instead of spending the one-time token again.
    func pairingRequestID(for token: UUID) throws -> UUID {
        let key = pairingRequestKey(for: token)
        lock.lock()
        defer { lock.unlock() }
        if let data = try read(service: service, account: key),
           let string = String(data: data, encoding: .utf8),
           let requestID = UUID(uuidString: string) {
            return requestID
        }
        let requestID = UUID()
        try write(Data(requestID.uuidString.utf8), service: service, account: key)
        return requestID
    }

    func clearPairingRequestID(for token: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try delete(service: service, account: pairingRequestKey(for: token))
    }

    private func pairingRequestKey(for token: UUID) -> String {
        let hash = SHA256.hash(data: Data(token.uuidString.utf8))
        let identifier = hash.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "pairing-request.\(identifier)"
    }

    private func query(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
    }

    private func read(service: String, account: String) throws -> Data? {
        var attributes = query(service: service, account: account)
        attributes[kSecReturnData] = kCFBooleanTrue
        attributes[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if Self.isAbsentSessionStatus(status) { return nil }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
        guard let data = result as? Data else { throw StorageError.unreadableData }
        return data
    }

    /// An unsigned simulator process has no application-identifier entitlement,
    /// so it cannot read any app-scoped Keychain item. Treat that specific
    /// simulator-only state as an empty session: the app can still show its
    /// signed-out gate, while any attempted credential write remains an
    /// explicit error. On a real device this status is always surfaced.
    static func isAbsentSessionStatus(_ status: OSStatus) -> Bool {
        if status == errSecItemNotFound { return true }
        #if targetEnvironment(simulator)
        return status == errSecMissingEntitlement
        #else
        return false
        #endif
    }

    private func write(_ data: Data, service: String, account: String) throws {
        let base = query(service: service, account: account)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StorageError.keychain(status) }
        var add = base
        attributes.forEach { add[$0.key] = $0.value }
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StorageError.keychain(addStatus) }
    }

    private func delete(service: String, account: String) throws {
        let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.keychain(status)
        }
    }
}
