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
        isRunningUIAutomation && ProcessInfo.processInfo.arguments.contains("-authGatePreview")
    }

    var requiresAccountAuthentication: Bool {
        if Self.isAuthGatePreview { return true }
        return workspaceEnvironment == .production && !Self.isRunningUIAutomation
    }

    var isAccountReady: Bool {
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
        guard requiresAccountAuthentication else {
            if case .ready = accountState { return }
            accountState = .ready(AccountSession(userID: "local", email: nil, workspaceID: workspaceID, membershipRole: "owner", isPairedDevice: false))
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
        } catch {
            accountState = .signedOut
        }
    }

    /// The anonymous entry point: a guest ledger that stays on this device.
    /// No Supabase session is created; sync remains off until the user signs
    /// in with a real account from Settings.
    func continueWithoutAccount() {
        if Self.isAuthGatePreview {
            accountState = .ready(localGuestSession())
            return
        }
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
            accountState = .authenticating
            return
        }
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

    /// Native Sign in with Apple: the system sheet already ran; exchange the
    /// identity token for a Supabase session. `nonce` is the RAW nonce whose
    /// SHA-256 digest was attached to the Apple request.
    func signInWithApple(result: Result<ASAuthorization, Error>, nonce: String) async {
        if Self.isAuthGatePreview {
            accountState = .authenticating
            return
        }
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                accountState = .failure(String(localized: "Apple did not return a valid identity token. Please try again."))
                return
            }
            guard hasSupabaseConfiguration else {
                accountState = .failure(String(localized: "This build is missing its Supabase configuration."))
                return
            }
            accountState = .authenticating
            do {
                let session = try await supabase().auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
                )
                await resolveWorkspace(for: session)
            } catch {
                accountState = .failure(authErrorMessage(error))
            }
        case let .failure(error):
            // Dismissing the system sheet is not an error state.
            if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
                return
            }
            accountState = .failure(authErrorMessage(error))
        }
    }

    func handleAuthCallback(_ url: URL) async {
        guard url.scheme == Self.oauthRedirectURL.scheme, hasSupabaseConfiguration else { return }
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
        guard hasSupabaseConfiguration else {
            accountState = .failure(String(localized: "This build is missing its Supabase configuration."))
            return
        }

        accountState = .authenticating
        do {
            let client = try supabase()
            let sessionTokens = try await requestDeviceSession(for: token)
            let deviceSession = try await client.auth.setSession(
                accessToken: sessionTokens.accessToken,
                refreshToken: sessionTokens.refreshToken
            )
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
        do {
            let pairedDevice = switch accountState {
            case let .ready(session): session.isPairedDevice
            case let .awaitingWorkspace(isPairedDevice): isPairedDevice
            default: false
            }
            if pairedDevice {
                let removed: Bool = try await supabase()
                    .rpc("earnline_disconnect_current_device")
                    .execute()
                    .value
                guard removed else { throw AccountAuthError.deviceNotFound }
            }
            try await supabase().auth.signOut(scope: .local)
        } catch {
            syncError = authErrorMessage(error)
            return
        }
        detachWorkspaceStore()
        workspaceID = workspaceEnvironment.workspaceID
        workspaceStoreIdentity = "\(workspaceEnvironment.rawValue):signed-out"
        accountState = .signedOut
        resetSupabaseClient()
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

            let pairedDevice = isPairedIdentity(session)
            activateResolvedWorkspace(membership.workspaceID, userID: session.user.id.uuidString)
            accountState = .ready(AccountSession(
                userID: session.user.id.uuidString,
                email: pairedDevice ? nil : session.user.email,
                workspaceID: membership.workspaceID,
                membershipRole: membership.membershipRole,
                isPairedDevice: pairedDevice
            ))
            syncMessage = String(localized: "Ready")
            syncError = nil
        } catch {
            accountState = .failure(authErrorMessage(error))
        }
    }

    private func activateResolvedWorkspace(_ resolvedWorkspaceID: String, userID: String) {
        // A resolved real account always supersedes a lingering guest flag.
        defaults.removeObject(forKey: Self.localGuestDefaultsKey)
        let previousUserID = defaults.string(forKey: "accountStoreFirstUserID")
        let isDifferentAccount = previousUserID != nil && previousUserID != userID
        workspaceID = resolvedWorkspaceID
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

    private func requestDeviceSession(for token: UUID) async throws -> DeviceSessionResponse {
        guard let baseURL = URL(string: supabaseURLString), !supabaseKey.isEmpty else {
            throw AccountAuthError.invalidResponse
        }
        let endpoint = baseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("earnline-pair-device")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["token": token.uuidString.lowercased()])
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

    private func applyAuthGatePreviewState() {
        let arguments = ProcessInfo.processInfo.arguments
        let stateIndex = arguments.firstIndex(of: "-authGateState")
        let state = stateIndex.flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        } ?? "signedOut"

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
