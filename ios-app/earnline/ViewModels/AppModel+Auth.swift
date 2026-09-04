import AuthenticationServices
import Foundation
import Supabase

/// Account identity and workspace membership are intentionally distinct from
/// the local App Lock. A successfully-unlocked app still cannot sync until a
/// production account has a Supabase session and a resolved membership.
extension AppModel {
    enum AccountState: Equatable {
        case checking
        case signedOut
        case authenticating
        case awaitingWorkspace(isPairedDevice: Bool)
        case ready(AccountSession)
        case failure(String)
    }

    struct AccountSession: Equatable {
        let userID: String
        let email: String?
        let workspaceID: String
        let membershipRole: String
        let isPairedDevice: Bool
        /// A guest ledger that lives only in this device's local store. There
        /// is no Supabase session behind it and it must never sync or pair.
        var isLocalOnly = false

        var isOwner: Bool { membershipRole == "owner" && !isPairedDevice && !isLocalOnly }
        var label: String {
            if isLocalOnly { return String(localized: "On this device") }
            if isPairedDevice { return String(localized: "Paired device") }
            return email ?? String(localized: "Signed-in account")
        }
    }

    struct PairingCode: Equatable {
        let token: UUID
        let expiresAt: Date

        var payload: String { "earnline-pairing://v1/\(token.uuidString.lowercased())" }
    }

    struct PairedDevice: Identifiable, Equatable {
        let id: UUID
        let createdAt: Date
        let lastSignInAt: Date?
    }

    private struct WorkspaceMembershipResponse: Decodable {
        let workspaceID: String
        let membershipRole: String

        enum CodingKeys: String, CodingKey {
            case workspaceID = "workspace_id"
            case membershipRole = "membership_role"
        }
    }

    private static let acceptedMembershipRoles: Set<String> = ["owner", "member", "device"]

    /// The last server-verified membership lets an already authenticated owner
    /// open their *local* ledger while transport is unavailable. It is never
    /// used for a server denial or for a different Supabase user, so an offline
    /// launch cannot turn a failed authorization check into cloud access.
    private struct CachedWorkspaceMembership: Codable {
        let userID: String
        let email: String?
        let workspaceID: String
        let membershipRole: String
        let isPairedDevice: Bool
    }

    private struct PairingTokenResponse: Decodable {
        let pairingToken: UUID
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case pairingToken = "pairing_token"
            case expiresAt = "expires_at"
        }
    }

    private struct PairedDeviceResponse: Decodable {
        let userID: UUID
        let createdAt: Date
        let lastSignInAt: Date?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case createdAt = "created_at"
            case lastSignInAt = "last_sign_in_at"
        }
    }

    private struct DeviceSessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private struct PairingFailureResponse: Decodable {
        let error: String
    }

    /// The callback scheme is the bundle ID (registered in Info.plist via
    /// `$(PRODUCT_BUNDLE_IDENTIFIER)`), so the side-by-side dev build gets its
    /// own scheme instead of fighting the App Store build over one. Each
    /// scheme in use must be in the Supabase redirect-URL allowlist.
    nonisolated static let oauthRedirectURL = URL(string: "\(Bundle.main.bundleIdentifier ?? "com.earnline.app")://auth/callback")!

    /// The dedicated local-only guest container identity. Deliberately not a
    /// real workspace: it never syncs, never migrates into an account store,
    /// and never appears in a sync payload.
    nonisolated static let localGuestWorkspaceID = "local-guest"
    nonisolated static let localGuestDefaultsKey = "localGuestMode"

    /// A UI-test-only route that keeps the real authentication gate visible
    /// while the rest of UI automation stays offline and in-memory. Production
    /// code never sets this argument.
    nonisolated static var isAuthGatePreview: Bool {
        #if DEBUG
        isRunningUIAutomation && hasUIAutomationLaunchFlag("-authGatePreview")
        #else
        false
        #endif
    }

    var requiresAccountAuthentication: Bool {
        // Dev is deliberately a local-only companion. It has no production
        // auth route, even if a configuration file contains development keys.
        guard !Self.isLocalOnlyDevBuild else { return false }
        if Self.isAuthGatePreview { return true }
        return workspaceEnvironment == .production && !Self.isRunningUIAutomation
    }

    /// Debug presets must be able to replace the ledger in the Dev companion
    /// even though that target never requires a production account.
    var isDebugAuthGatePreview: Bool {
        #if DEBUGMENU
        debugAuthGatePreview
        #else
        false
        #endif
    }

    var isAccountReady: Bool {
        if isDebugAuthGatePreview {
            if case .ready = accountState { return true }
            return false
        }
        guard requiresAccountAuthentication else { return true }
        if case .ready = accountState { return true }
        return false
    }

    var accountSession: AccountSession? {
        guard case let .ready(session) = accountState else { return nil }
        return session
    }

    func bootstrapAuthentication() async {
        if Self.isAuthGatePreview {
            applyAuthGatePreviewState()
            return
        }
        #if DEBUGMENU
        // A debug preview owns its visible state. Never let a bootstrap task
        // replace it or start a client while someone is testing a scenario.
        if isDebugAuthGatePreview { return }
        #endif
        guard requiresAccountAuthentication else {
            if case .ready = accountState { return }
            accountState = .ready(AccountSession(
                userID: "local",
                email: nil,
                workspaceID: workspaceID,
                membershipRole: "owner",
                isPairedDevice: false
            ))
            return
        }
        if defaults.bool(forKey: Self.localGuestDefaultsKey) {
            activateLocalGuestWorkspace()
            return
        }
        guard hasSupabaseConfiguration else {
            accountState = .failure(String(localized: "This build is missing its Supabase configuration."))
            return
        }

        accountState = .checking
        do {
            let session = try await supabase().auth.session
            await resolveWorkspace(for: session)
        } catch let error as EarnlineAuthStorage.StorageError {
            accountState = .failure(error.localizedDescription)
        } catch {
            accountState = .signedOut
        }
    }

    /// The anonymous entry point: a guest ledger that stays on this device.
    /// No Supabase session is created; sync remains off until the user signs
    /// in with a real account. Deliberately an explicit choice on the gate
    /// rather than a silent fallback — a failed account check must not quietly
    /// hand someone a different, unsynced ledger.
    func continueWithoutAccount() {
        if Self.isAuthGatePreview {
            accountState = .ready(localGuestSession())
            return
        }
        #if DEBUGMENU
        if isDebugAuthGatePreview {
            debugCompleteAuthPreview()
            return
        }
        #endif
        defaults.set(true, forKey: Self.localGuestDefaultsKey)
        activateLocalGuestWorkspace()
    }

    /// Leaves guest mode and returns to the sign-in gate. The guest store
    /// stays on disk untouched, so choosing guest again restores it.
    func leaveGuestMode() {
        defaults.removeObject(forKey: Self.localGuestDefaultsKey)
        detachWorkspaceStore()
        workspaceID = workspaceEnvironment.workspaceID
        workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):signed-out"
        accountState = .signedOut
        resetSupabaseClient()
    }

    private func activateLocalGuestWorkspace() {
        detachWorkspaceStore()
        workspaceID = Self.localGuestWorkspaceID
        loadOnboardingState()
        // The guest container intentionally uses `.account` mode so it maps to
        // its own SwiftData file and can never touch the legacy cache that the
        // first resolved real account is entitled to migrate.
        accountStoreMode = .account
        workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):\(Self.localGuestWorkspaceID):\(AccountStoreMode.account.rawValue)"
        accountState = .ready(localGuestSession())
    }

    private func localGuestSession() -> AccountSession {
        AccountSession(
            userID: "local-guest",
            email: nil,
            workspaceID: Self.localGuestWorkspaceID,
            membershipRole: "owner",
            isPairedDevice: false,
            isLocalOnly: true
        )
    }

    func signInWithOAuth(
        provider: Provider,
        launchFlow: @escaping @MainActor @Sendable (URL) async throws -> URL
    ) async {
        if Self.isAuthGatePreview {
            _ = provider
            accountState = .authenticating
            return
        }
        #if DEBUGMENU
        if isDebugAuthGatePreview {
            _ = provider
            debugBeginAuthenticating(provider: "External provider")
            return
        }
        #endif
        guard hasSupabaseConfiguration else {
            accountState = .failure(String(localized: "This build is missing its Supabase configuration."))
            return
        }
        accountState = .authenticating
        do {
            let session = try await supabase().auth.signInWithOAuth(
                provider: provider,
                redirectTo: Self.oauthRedirectURL,
                launchFlow: launchFlow
            )
            await resolveWorkspace(for: session)
        } catch {
            accountState = .failure(authErrorMessage(error))
        }
    }

    func handleAuthCallback(_ url: URL) async {
        guard Self.isExpectedOAuthCallback(url), hasSupabaseConfiguration else { return }
        do {
            let session = try await supabase().auth.session(from: url)
            await resolveWorkspace(for: session)
        } catch {
            accountState = .failure(authErrorMessage(error))
        }
    }

    func retryWorkspaceResolution() async {
        if Self.isAuthGatePreview {
            accountState = .ready(previewAccountSession(isPairedDevice: false))
            return
        }
        #if DEBUGMENU
        if isDebugAuthGatePreview {
            debugCompleteAuthPreview()
            return
        }
        #endif
        guard hasSupabaseConfiguration else { return }
        accountState = .checking
        do {
            let session = try await supabase().auth.session
            await resolveWorkspace(for: session)
        } catch {
            accountState = .signedOut
        }
    }

    func createPairingCode() async throws -> PairingCode {
        if Self.isAuthGatePreview {
            return PairingCode(
                token: UUID(uuidString: "4C4B8B18-6E55-4B04-B3EC-5B4B2B3AA97C")!,
                expiresAt: .now.addingTimeInterval(10 * 60)
            )
        }
        guard let accountSession, accountSession.isOwner else {
            throw AccountAuthError.ownerRequired
        }
        let rows: [PairingTokenResponse] = try await supabase()
            .rpc("earnline_create_pairing_token")
            .execute()
            .value
        guard let result = rows.first else { throw AccountAuthError.invalidResponse }
        return PairingCode(token: result.pairingToken, expiresAt: result.expiresAt)
    }

    func redeemPairingCode(_ rawValue: String) async {
        guard let token = Self.pairingToken(from: rawValue) else {
            accountState = .failure(String(localized: "Enter a valid pairing code."))
            return
        }
        if Self.isAuthGatePreview {
            _ = token
            accountState = .ready(previewAccountSession(isPairedDevice: true))
            return
        }
        #if DEBUGMENU
        if isDebugAuthGatePreview {
            _ = token
            debugCompleteAuthPreview()
            return
        }
        #endif
        guard hasSupabaseConfiguration else {
            accountState = .failure(String(localized: "This build is missing its Supabase configuration."))
            return
        }

        accountState = .authenticating
        do {
            let client = try supabase()
            guard let authStorage else { throw AccountAuthError.invalidResponse }
            let requestID = try authStorage.pairingRequestID(for: token)
            let sessionTokens = try await requestDeviceSession(for: token, requestID: requestID)
            let deviceSession = try await client.auth.setSession(
                accessToken: sessionTokens.accessToken,
                refreshToken: sessionTokens.refreshToken
            )
            try authStorage.clearPairingRequestID(for: token)
            await resolveWorkspace(for: deviceSession)
        } catch {
            accountState = .failure(authErrorMessage(error))
        }
    }

    func pairedDevices() async throws -> [PairedDevice] {
        if Self.isAuthGatePreview {
            return [PairedDevice(
                id: UUID(uuidString: "BD078F2D-D828-4D64-B631-69E2C28D046E")!,
                createdAt: .now.addingTimeInterval(-14 * 24 * 60 * 60),
                lastSignInAt: .now.addingTimeInterval(-2 * 60 * 60)
            )]
        }
        guard let accountSession, accountSession.isOwner else {
            throw AccountAuthError.ownerRequired
        }
        let rows: [PairedDeviceResponse] = try await supabase()
            .rpc("earnline_list_devices")
            .execute()
            .value
        return rows.map { PairedDevice(id: $0.userID, createdAt: $0.createdAt, lastSignInAt: $0.lastSignInAt) }
    }

    func revokePairedDevice(_ device: PairedDevice) async throws {
        if Self.isAuthGatePreview { return }
        guard let accountSession, accountSession.isOwner else {
            throw AccountAuthError.ownerRequired
        }
        let removed: Bool = try await supabase()
            .rpc("earnline_revoke_device", params: ["p_user_id": device.id.uuidString])
            .execute()
            .value
        guard removed else { throw AccountAuthError.deviceNotFound }
    }

    func signOutAccount() async {
        if Self.isAuthGatePreview {
            accountState = .signedOut
            return
        }
        #if DEBUGMENU
        if isDebugAuthGatePreview {
            debugShowAuthPreview(.signedOut)
            return
        }
        #endif
        let pairedDevice = switch accountState {
        case let .ready(session): session.isPairedDevice
        case let .awaitingWorkspace(isPairedDevice): isPairedDevice
        default: false
        }
        var remoteDisconnectFailure: Error?

        if pairedDevice {
            do {
                let removed: Bool = try await supabase()
                    .rpc("earnline_disconnect_current_device")
                    .execute()
                    .value
                if !removed { remoteDisconnectFailure = AccountAuthError.deviceNotFound }
            } catch {
                remoteDisconnectFailure = error
            }
        }

        // Supabase may treat Keychain failures as best effort. Remove the
        // namespaced session ourselves and refuse to claim a local sign-out if
        // secure storage could not actually be cleared.
        var sdkSignOutFailure: Error?
        var storageFailure: Error?
        var storage: EarnlineAuthStorage?
        do {
            let client = try supabase()
            storage = authStorage
            try await client.auth.signOut(scope: .local)
        } catch {
            // The SDK may report a transport or its own best-effort storage
            // failure. The explicit delete below is the local source of truth.
            sdkSignOutFailure = error
        }
        guard let storage else {
            accountState = .failure(String(
                localized: "Could not access secure sign-in data on this iPhone. Unlock it and choose Sign out again."
            ))
            return
        }
        do {
            try storage.removeSession()
        } catch {
            storageFailure = error
        }
        if let storageFailure {
            accountState = .failure(String(
                // swiftlint:disable:next line_length
                localized: "Could not remove secure sign-in data from this iPhone. Unlock it and choose Sign out again. \(storageFailure.localizedDescription)"
            ))
            return
        }
        detachWorkspaceStore()
        workspaceID = workspaceEnvironment.workspaceID
        workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):signed-out"
        resetSupabaseClient()

        if remoteDisconnectFailure != nil {
            let message: String
            if pairedDevice {
                // swiftlint:disable:next line_length
                message = String(localized: "Signed out on this iPhone. This paired device could not be disconnected from your workspace while offline. Reconnect it, then revoke it from your owner device.")
            } else {
                message = String(localized: "Signed out on this iPhone. The server could not be reached to end this session remotely.")
            }
            accountState = .failure(message)
        } else if sdkSignOutFailure != nil {
            accountState = .failure(String(
                // swiftlint:disable:next line_length
                localized: "Signed out on this iPhone. Secure sign-in data was removed, but Supabase could not finish its own sign-out cleanup."
            ))
        } else {
            accountState = .signedOut
        }
    }

    private func resolveWorkspace(for session: Session) async {
        do {
            let rows: [WorkspaceMembershipResponse] = try await supabase()
                .rpc("earnline_current_workspace")
                .execute()
                .value
            guard let membership = rows.first else {
                accountState = .awaitingWorkspace(isPairedDevice: isPairedIdentity(session))
                return
            }

            guard !membership.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Self.acceptedMembershipRoles.contains(membership.membershipRole) else {
                throw AccountAuthError.invalidResponse
            }

            let pairedDevice = isPairedIdentity(session)
            activateResolvedWorkspace(membership.workspaceID, userID: session.user.id.uuidString)
            let account = AccountSession(
                userID: session.user.id.uuidString,
                email: pairedDevice ? nil : session.user.email,
                workspaceID: membership.workspaceID,
                membershipRole: membership.membershipRole,
                isPairedDevice: pairedDevice
            )
            cacheVerifiedMembership(account)
            accountState = .ready(account)
            syncMessage = String(localized: "Ready")
            syncError = nil
        } catch {
            if Self.isOfflineTransportError(error), restoreCachedMembership(for: session) {
                return
            }
            accountState = .failure(authErrorMessage(error))
        }
    }

    private func cacheVerifiedMembership(_ account: AccountSession) {
        let membership = CachedWorkspaceMembership(
            userID: account.userID,
            email: account.email,
            workspaceID: account.workspaceID,
            membershipRole: account.membershipRole,
            isPairedDevice: account.isPairedDevice
        )
        do {
            let data = try JSONEncoder().encode(membership)
            defaults.set(data, forKey: Self.cachedMembershipKey(for: account.userID))
        } catch {
            // Online authorization remains valid, but make it clear that the
            // offline fallback could not be refreshed for this device.
            // swiftlint:disable:next line_length
            accountSecurityNotice = String(localized: "Earnline could not save this iPhone’s offline workspace check. Online sync still works, but offline access may require signing in again.")
        }
    }

    /// Restoring this cache only makes the on-device SwiftData ledger usable.
    /// `isSupabaseConfigured` remains subject to the normal network sync path,
    /// and the next successful membership request replaces this cached record.
    private func restoreCachedMembership(for session: Session) -> Bool {
        let userID = session.user.id.uuidString
        guard let data = defaults.data(forKey: Self.cachedMembershipKey(for: userID)),
              let membership = try? JSONDecoder().decode(CachedWorkspaceMembership.self, from: data),
              membership.userID == userID,
              membership.isPairedDevice == isPairedIdentity(session) else {
            return false
        }
        activateResolvedWorkspace(membership.workspaceID, userID: userID)
        accountState = .ready(AccountSession(
            userID: membership.userID,
            email: membership.email,
            workspaceID: membership.workspaceID,
            membershipRole: membership.membershipRole,
            isPairedDevice: membership.isPairedDevice
        ))
        syncMessage = String(localized: "Offline")
        syncError = String(localized: "You're offline. Showing your last verified workspace access on this iPhone.")
        return true
    }

    private static func cachedMembershipKey(for userID: String) -> String {
        "cachedWorkspaceMembership.\(userID)"
    }

    /// A membership response that was rejected by Supabase must fail closed.
    /// Only concrete URL transport failures are eligible for the local-cache
    /// fallback above; HTTP 401/403 and decoded RPC errors never match here.
    static func isOfflineTransportError(_ error: Error) -> Bool {
        let networkCodes: Set<URLError.Code> = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .timedOut,
            .dataNotAllowed,
            .internationalRoamingOff
        ]
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           networkCodes.contains(URLError.Code(rawValue: nsError.code)) {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            let underlyingNSError = underlyingError as NSError
            guard underlyingNSError.domain != nsError.domain || underlyingNSError.code != nsError.code else {
                return false
            }
            return isOfflineTransportError(underlyingError)
        }
        return false
    }

    private func activateResolvedWorkspace(_ resolvedWorkspaceID: String, userID: String) {
        // A resolved real account always supersedes a lingering guest flag.
        defaults.removeObject(forKey: Self.localGuestDefaultsKey)
        let previousUserID = defaults.string(forKey: "accountStoreFirstUserID")
        let isDifferentAccount = previousUserID != nil && previousUserID != userID
        workspaceID = resolvedWorkspaceID
        loadOnboardingState()
        defaults.set(resolvedWorkspaceID, forKey: "workspaceID")
        defaults.set(resolvedWorkspaceID, forKey: "workspaceID.\(workspaceEnvironment.rawValue)")
        syncGeneration += 1
        detachWorkspaceStore()
        // A different account never touches the legacy cache. The very first
        // resolved account may finish one authenticated sync from that cache,
        // after which `completeAccountStoreMigrationAfterSuccessfulSync()`
        // switches it to an account-scoped container without deleting the old
        // file.
        accountStoreMode = isDifferentAccount || defaults.bool(forKey: "accountStoreMigrated.\(resolvedWorkspaceID)")
            ? .account
            : .legacy
        workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):\(resolvedWorkspaceID):\(accountStoreMode.rawValue)"
    }

    func completeAccountStoreMigrationAfterSuccessfulSync() {
        guard workspaceEnvironment == .production,
              accountStoreMode == .legacy,
              let accountSession else { return }
        defaults.set(true, forKey: "accountStoreMigrated.\(workspaceID)")
        defaults.set(accountSession.userID, forKey: "accountStoreFirstUserID")
        accountStoreMode = .account
        workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):\(workspaceID):\(accountStoreMode.rawValue)"
    }

    /// A legacy SwiftData file that can no longer be opened must not block the
    /// owner from reaching their authenticated workspace. This only changes the
    /// active cache identity; it never deletes, moves, or imports the legacy
    /// SQLite files. The recovery UI asks for an explicit confirmation first.
    var canCreateFreshAccountStoreAfterRecovery: Bool {
        guard workspaceEnvironment == .production,
              accountStoreMode == .legacy,
              let accountSession else { return false }
        return !accountSession.isLocalOnly
    }

    func createFreshAccountStoreAfterRecovery() {
        guard canCreateFreshAccountStoreAfterRecovery else { return }
        defaults.set(true, forKey: "accountStoreMigrated.\(workspaceID)")
        accountStoreMode = .account
        workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):\(workspaceID):\(accountStoreMode.rawValue)"
    }

    private func authErrorMessage(_ error: Error) -> String {
        if let authenticationError = error as? ASWebAuthenticationSessionError,
           authenticationError.code == .canceledLogin {
            return String(localized: "Sign in was cancelled. Choose a provider when you’re ready.")
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(localized: "Could not complete account setup. Please try again.") : message
    }

    private func isPairedIdentity(_ session: Session) -> Bool {
        session.user.isAnonymous || session.user.appMetadata["earnline_device"]?.boolValue == true
    }

    private func requestDeviceSession(for token: UUID, requestID: UUID) async throws -> DeviceSessionResponse {
        guard let baseURL = URL(string: supabaseURLString), !supabaseKey.isEmpty else {
            throw AccountAuthError.invalidResponse
        }
        let endpoint = baseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("earnline-pair-device")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode([
            "token": token.uuidString.lowercased(),
            "request_id": requestID.uuidString.lowercased(),
        ])
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "authorization")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let safeMessage = (try? JSONDecoder().decode(PairingFailureResponse.self, from: data).error)
                ?? String(localized: "This device could not be paired.")
            throw AccountAuthError.pairingFailed(safeMessage)
        }
        return try JSONDecoder().decode(DeviceSessionResponse.self, from: data)
    }

    private static func pairingToken(from value: String) -> UUID? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = UUID(uuidString: trimmed) { return direct }
        guard let url = URL(string: trimmed),
              url.scheme == "earnline-pairing",
              url.host == "v1" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    nonisolated static func isExpectedOAuthCallback(_ url: URL) -> Bool {
        url.scheme == oauthRedirectURL.scheme
            && url.host == oauthRedirectURL.host
            && url.path == oauthRedirectURL.path
    }

    /// Places the gate in one deterministic state for UI automation. Driven by
    /// `-authGateState` (or `EARNLINE_UI_TEST_AUTH_GATE_STATE`) so each test
    /// can photograph a single state without a provider or a network.
    private func applyAuthGatePreviewState() {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        let environmentState = processInfo.environment["EARNLINE_UI_TEST_AUTH_GATE_STATE"]
        let arguments = processInfo.arguments
        let stateIndex = arguments.firstIndex(of: "-authGateState")
        let argumentState = stateIndex.flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        let state = environmentState ?? argumentState ?? "signedOut"

        switch state {
        case "checking":
            accountState = .checking
        case "authenticating":
            accountState = .authenticating
        case "failure":
            accountState = .failure(String(localized: "Could not complete account setup. Please try again."))
        case "workspacePending":
            accountState = .awaitingWorkspace(isPairedDevice: false)
        case "pairedWorkspacePending":
            accountState = .awaitingWorkspace(isPairedDevice: true)
        case "ready":
            accountState = .ready(previewAccountSession(isPairedDevice: false))
        default:
            accountState = .signedOut
        }
        #else
        accountState = .signedOut
        #endif
    }

    private func previewAccountSession(isPairedDevice: Bool) -> AccountSession {
        AccountSession(
            userID: isPairedDevice ? "ui-test-paired-device" : "ui-test-owner",
            email: isPairedDevice ? nil : "owner@example.com",
            workspaceID: workspaceID,
            membershipRole: isPairedDevice ? "device" : "owner",
            isPairedDevice: isPairedDevice
        )
    }
}

enum AccountAuthError: LocalizedError {
    case ownerRequired
    case invalidResponse
    case deviceNotFound
    case pairingFailed(String)

    var errorDescription: String? {
        switch self {
        case .ownerRequired: return String(localized: "Only the workspace owner can pair a device.")
        case .invalidResponse: return String(localized: "The pairing service returned an invalid response.")
        case .deviceNotFound: return String(localized: "This paired device is no longer connected.")
        case let .pairingFailed(message): return message
        }
    }
}
