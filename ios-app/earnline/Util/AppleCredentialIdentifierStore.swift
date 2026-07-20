import Foundation
import Security

/// Stores only Apple's opaque, non-secret user identifier. The identifier is
/// tied to a Supabase user ID so a later session can be checked for Apple
/// credential revocation without ever persisting an Apple identity token.
actor AppleCredentialIdentifierStore {
    static let shared = AppleCredentialIdentifierStore()

    private let service: String

    init(service: String = "\(Bundle.main.bundleIdentifier ?? "com.earnline.app").apple-credential-identifier") {
        self.service = service
    }

    func save(_ appleUserIdentifier: String, forSupabaseUserID supabaseUserID: String) throws {
        let baseQuery = query(for: supabaseUserID)
        var addQuery = baseQuery
        addQuery[kSecValueData] = Data(appleUserIdentifier.utf8)
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updates: [CFString: Any] = [kSecValueData: Data(appleUserIdentifier.utf8)]
            let status = SecItemUpdate(baseQuery as CFDictionary, updates as CFDictionary)
            guard status == errSecSuccess else { throw AppleCredentialIdentifierStoreError.status(status) }
        default:
            throw AppleCredentialIdentifierStoreError.status(addStatus)
        }
    }

    func load(forSupabaseUserID supabaseUserID: String) throws -> String? {
        var lookupQuery = query(for: supabaseUserID)
        lookupQuery[kSecReturnData] = true
        lookupQuery[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let identifier = String(data: data, encoding: .utf8),
                  !identifier.isEmpty else {
                throw AppleCredentialIdentifierStoreError.unexpectedData
            }
            return identifier
        case errSecItemNotFound:
            return nil
        default:
            throw AppleCredentialIdentifierStoreError.status(status)
        }
    }

    func remove(forSupabaseUserID supabaseUserID: String) throws {
        let status = SecItemDelete(query(for: supabaseUserID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleCredentialIdentifierStoreError.status(status)
        }
    }

    private func query(for supabaseUserID: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: supabaseUserID
        ]
    }
}

enum AppleCredentialIdentifierStoreError: Error {
    case unexpectedData
    case status(OSStatus)
}
