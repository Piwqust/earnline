import AuthenticationServices
import CryptoKit
import Security
import Supabase
import SwiftUI

/// The production entry point for a private Earnline workspace.
///
/// The anatomy follows the Figma "MainPage" gate (node 389-3889): a live,
/// scripted preview of the actual ledger fills the screen, and a black
/// bottom panel carries the brand line plus every way in — Apple as the
/// solid primary, Google/GitHub as icon-only glass pills, and the two
/// local-only routes beneath their own divider.
struct AuthGateView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var showingPairDevice = false
    @State private var readyFeedback = false
    @State private var selectedProviderName: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            AuthBackdropPreview()

            AuthGatePanel(
                state: app.accountState,
                selectedProviderName: selectedProviderName,
                pair: { showingPairDevice = true },
                guest: { app.continueWithoutAccount() },
                signIn: signIn,
                signInApple: signInWithApple,
                retry: { Task { await app.retryWorkspaceResolution() } },
                signOut: { Task { await app.signOutAccount() } }
            )
        }
        .sheet(isPresented: $showingPairDevice) {
            PairDeviceRedeemSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0), value: app.accountState)
        .onChange(of: app.accountState) { _, state in
            if case .ready = state {
                showingPairDevice = false
                readyFeedback.toggle()
            }
        }
        .sensoryFeedback(.success, trigger: readyFeedback)
    }

    private func signInWithApple(_ result: Result<ASAuthorization, Error>, nonce: String) {
        selectedProviderName = "Apple"
        Task { await app.signInWithApple(result: result, nonce: nonce) }
    }

    private func signIn(_ provider: Provider) {
        selectedProviderName = switch provider {
        case .google: "Google"
        case .github: "GitHub"
        default: "Account"
        }
        Task {
            await app.signInWithOAuth(provider: provider) { url in
                try await webAuthenticationSession.authenticate(
                    using: url,
                    callbackURLScheme: AppModel.oauthRedirectURL.scheme!
                )
            }
        }
    }
}

// MARK: - Bottom panel

/// The black bottom card from the Figma: 50 pt top corners, a deep upward
/// shadow, and content that morphs between the account states. The panel is
/// dark in both appearances — only the backdrop follows the system scheme.
private struct AuthGatePanel: View {
    let state: AppModel.AccountState
    let selectedProviderName: String?
    let pair: () -> Void
    let guest: () -> Void
    let signIn: (Provider) -> Void
    let signInApple: (Result<ASAuthorization, Error>, String) -> Void
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        content
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 50, topTrailingRadius: 50, style: .continuous)
                    .fill(Color(hex: "#000003"))
                    .shadow(color: .black.opacity(0.25), radius: 44, y: -24)
                    .ignoresSafeArea(edges: .bottom)
            }
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .checking:
            checkingContent

        // One branch for all three so the panel keeps a stable identity:
        // the glass buttons morph in place instead of remounting.
        case .signedOut, .authenticating, .failure:
            entryContent

        case let .awaitingWorkspace(isPairedDevice):
            workspacePendingContent(isPairedDevice: isPairedDevice)

        case .ready:
            EmptyView()
        }
    }

    // MARK: Checking

    private var checkingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("Checking your workspace…")
                .appFont(15, .medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("auth.checking")
    }

    // MARK: Entry

    private var errorMessage: String? {
        if case let .failure(message) = state { return message }
        return nil
    }

    private var authenticatingProvider: String? {
        if case .authenticating = state { return selectedProviderName ?? "Google" }
        return nil
    }

    private var identifier: String {
        switch state {
        case .authenticating: "auth.authenticating"
        case .failure: "auth.failure"
        default: "auth.entry"
        }
    }

    private var entryContent: some View {
        VStack(spacing: 0) {
            Text(verbatim: "TRACK КАЖДЫЙ INCOME")
                .appFont(24, .semibold)
                .tracking(-0.24)
                .foregroundStyle(.white.opacity(0.96))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                if let errorMessage {
                    AuthInlineNotice(label: "Sign-in issue", message: errorMessage)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                }

                if authenticatingProvider != nil {
                    Text("Opening your workspace…")
                        .appFont(15)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 16) {
                        AuthAppleButton(
                            isDisabled: authenticatingProvider != nil,
                            onComplete: signInApple
                        )

                        HStack(spacing: 16) {
                            AuthIconProviderButton(
                                title: "Continue with Google",
                                assetName: "GoogleG",
                                isAuthenticating: authenticatingProvider == "Google",
                                isDisabled: authenticatingProvider != nil
                            ) {
                                signIn(.google)
                            }

                            AuthIconProviderButton(
                                title: "Continue with GitHub",
                                assetName: "GitHubMark",
                                isAuthenticating: authenticatingProvider == "GitHub",
                                isDisabled: authenticatingProvider != nil
                            ) {
                                signIn(.github)
                            }
                        }
                    }
                }
            }
            .padding(.top, 30)

            localOnlyDivider
                .padding(.top, 30)

            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 16) {
                    AuthTertiaryButton(
                        title: "Continue without an account",
                        hint: "Keeps your ledger only on this device",
                        isDisabled: authenticatingProvider != nil,
                        action: guest
                    )

                    AuthTertiaryButton(
                        title: "Pair a device",
                        hint: "Use a one-time QR code to connect this device",
                        isDisabled: authenticatingProvider != nil,
                        action: pair
                    )
                }
            }
            .padding(.top, 20)
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var localOnlyDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .accessibilityHidden(true)
            Text("Local-only options")
                .appFont(14, .medium)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    // MARK: Awaiting workspace

    private func workspacePendingContent(isPairedDevice: Bool) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 9) {
                Text(isPairedDevice ? "Finish pairing this device" : "Finish setting up your workspace")
                    .appFont(22, .bold)
                    .foregroundStyle(.white.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)
                Text(isPairedDevice
                     ? "Scan a one-time code from your owner device. The code connects this device only."
                     : "One workspace step remains. When it is ready, come back here and we’ll open your ledger.")
                    .appFont(15)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 16) {
                    Button(action: retry) {
                        Text("Check again")
                            .appFont(17, .semibold)
                            .foregroundStyle(Color(hex: "#1A1A1A"))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.white)

                    if isPairedDevice {
                        AuthTertiaryButton(
                            title: "Pair this device",
                            hint: "Use a one-time QR code to connect this device",
                            isDisabled: false,
                            action: pair
                        )
                    }
                }
            }

            Button(role: .cancel, action: signOut) {
                Text("Sign out")
                    .appFont(15, .medium)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(minHeight: 44)
            }
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Buttons

/// An icon-only provider pill: the official brand mark centered in a glass
/// capsule, swapped for a spinner while that provider's flow is in flight.
/// The full "Continue with …" phrase lives in the accessibility label.
private struct AuthIconProviderButton: View {
    let title: LocalizedStringKey
    let assetName: String
    let isAuthenticating: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                        // Fixed size on purpose: a brand mark, not text — it
                        // must not grow with Dynamic Type.
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        // The in-flight provider keeps its look (only hit-testing is
        // dropped); the other options get the real disabled wash.
        .disabled(isDisabled && !isAuthenticating)
        .allowsHitTesting(!isDisabled)
        .accessibilityLabel(title)
        .accessibilityHint(isAuthenticating ? "Opening your workspace…" : "Opens secure sign in")
    }
}

/// A full-width quiet glass pill for the local-only routes.
private struct AuthTertiaryButton: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(17, .medium)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .disabled(isDisabled)
        .accessibilityHint(hint)
    }
}

/// The system Sign in with Apple control in the primary slot: the one solid
/// button in the cluster — always white on the black panel — clipped to the
/// same capsule as its glass siblings. On completion it hands the
/// authorization and the RAW nonce (whose SHA-256 digest rode the request)
/// to the model.
private struct AuthAppleButton: View {
    let isDisabled: Bool
    let onComplete: (Result<ASAuthorization, Error>, String) -> Void

    @State private var rawNonce = ""

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            rawNonce = AppleSignInNonce.random()
            request.requestedScopes = [.email]
            request.nonce = AppleSignInNonce.sha256(rawNonce)
        } onCompletion: { result in
            onComplete(result, rawNonce)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .clipShape(Capsule())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityIdentifier("auth.apple")
    }
}

private enum AppleSignInNonce {
    static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            // SecRandom failing is effectively unheard of; two random UUIDs
            // still carry ample entropy for a one-shot login nonce.
            return UUID().uuidString + UUID().uuidString
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Inline notice

struct AuthInlineNotice: View {
    let label: LocalizedStringKey
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.statusProgress)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.statusProgress.opacity(0.30), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
