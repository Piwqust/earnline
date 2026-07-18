import Foundation
import Testing
@testable import earnline

@Suite(.serialized)
struct AppleCredentialIdentifierStoreTests {
    // Debug simulator builds intentionally do not carry a signing identity or
    // keychain access group. Keep the real Security.framework integration
    // check on a signed iPhone, where Sign in with Apple itself is testable.
    @Test(.enabled(if: Self.runsOnPhysicalDevice))
    func storeRoundTripsAndUpdatesAnAppleIdentifier() async throws {
        let store = AppleCredentialIdentifierStore(service: "AppleCredentialIdentifierStoreTests.\(UUID().uuidString)")
        let userID = "supabase-user"
        try await store.remove(forSupabaseUserID: userID)

        try await store.save("apple-user-one", forSupabaseUserID: userID)
        #expect(try await store.load(forSupabaseUserID: userID) == "apple-user-one")

        try await store.save("apple-user-two", forSupabaseUserID: userID)
        #expect(try await store.load(forSupabaseUserID: userID) == "apple-user-two")

        try await store.remove(forSupabaseUserID: userID)
        #expect(try await store.load(forSupabaseUserID: userID) == nil)
    }

    private static var runsOnPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
}
