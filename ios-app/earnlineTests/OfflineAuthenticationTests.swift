import Foundation
import Supabase
import Testing
@testable import earnline

@MainActor
@Suite(.serialized)
struct OfflineAuthenticationTests {
    @Test(arguments: ["offline", "rejected", "missing-membership", "different-user", "missing-session"])
    func expiredSessionOnlyRestoresItsVerifiedOfflineWorkspace(scenario: String) async throws {
        let suite = "offline-auth-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let userID = UUID()
        let session = Session(accessToken: "expired-fixture", tokenType: "bearer", expiresIn: 1,
            expiresAt: Date.now.addingTimeInterval(-3600).timeIntervalSince1970, refreshToken: "fixture-refresh",
            user: User(id: userID, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: .now, updatedAt: .now))
        if scenario != "missing-membership" {
            let membership: [String: Any] = [
                "userID": scenario == "different-user" ? UUID().uuidString : userID.uuidString,
                "workspaceID": "offline-fixture", "membershipRole": "owner", "isPairedDevice": false,
            ]
            defaults.set(try JSONSerialization.data(withJSONObject: membership),
                         forKey: "cachedWorkspaceMembership.\(userID.uuidString)")
        }
        defaults.set(true, forKey: "accountStoreMigrated.offline-fixture")
        let app = AppModel(defaults: defaults)
        app.workspaceEnvironment = .production
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineAuthTransport.self]
        OfflineAuthTransport.rejectsSession = scenario == "rejected"
        let storage = FixtureSessionStorage(data: scenario == "missing-session" ? nil : try JSONEncoder().encode(session))
        let client = SupabaseClient(supabaseURL: URL(string: "https://offline-fixture.invalid")!, supabaseKey: "fixture",
            options: .init(auth: .init(storage: storage, storageKey: "fixture", autoRefreshToken: false,
                                      emitLocalSessionAsInitialSession: true),
                           global: .init(session: URLSession(configuration: configuration))))
        app.supabaseClient = client
        await app.restoreAuthentication()
        if scenario == "offline" {
            let account = try #require(app.accountSession)
            #expect(account.userID == userID.uuidString)
            #expect(account.workspaceID == "offline-fixture")
            #expect(!account.isLocalOnly)
            #expect(app.workspaceStoreIdentity == "production:offline-fixture:account")
            #expect(app.syncMessage == String(localized: "Offline"))
        } else {
            #expect(app.accountSession == nil)
        }
    }
}

private struct FixtureSessionStorage: AuthLocalStorage {
    let data: Data?
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { key == "fixture" ? data : nil }
    func remove(key: String) throws {}
}

private final class OfflineAuthTransport: URLProtocol {
    nonisolated(unsafe) static var rejectsSession = false
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        if Self.rejectsSession {
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"code":"refresh_token_not_found","message":"Revoked"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }
}
