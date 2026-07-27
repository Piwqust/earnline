#if DEBUGMENU
import SwiftUI

/// A local-only account/onboarding simulator for `earnline Dev`.
///
/// The release app intentionally opens directly to the ledger. This surface
/// exists so product and QA work can still inspect the account journey,
/// sign-out state, pairing handoff, and recoverable errors without touching a
/// provider, Supabase session, or SwiftData store.
struct DebugAuthGateView: View {
    @Environment(AppModel.self) private var app

    @State private var isOnboardingVideoMuted = true
    @State private var dockHeight: CGFloat = 340

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottom) {
                AuthBackdropVideo(
                    isActive: videoIsActive,
                    isMuted: isOnboardingVideoMuted,
                    dockHeight: dockHeight
                )

                LinearGradient(
                    colors: [.clear, .black.opacity(0.24)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)

                panel
            }
            .overlay(alignment: .top) {
                header
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.22), value: app.accountState)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                app.debugCompleteAuthPreview()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(verbatim: "Return to ledger"))
            .accessibilityIdentifier("debug.auth.close")

            Text(verbatim: "DEBUG · LOCAL AUTH PREVIEW")
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.48), in: Capsule())
                .accessibilityLabel(Text(verbatim: "Debug local authentication preview"))

            Spacer(minLength: 0)

            if videoIsActive {
                Button {
                    isOnboardingVideoMuted.toggle()
                } label: {
                    Image(systemName: isOnboardingVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text(verbatim: isOnboardingVideoMuted ? "Enable onboarding video sound" : "Mute onboarding video sound"))
                .accessibilityIdentifier("debug.auth.videoSound")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var panel: some View {
        ScrollView {
            stateContent
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 520)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(.black.opacity(0.96))
                .shadow(color: .black.opacity(0.36), radius: 36, y: -16)
                .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            dockHeight = height
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch app.accountState {
        case .checking:
            checkingContent
        case .signedOut, .authenticating, .failure:
            entryContent
        case let .awaitingWorkspace(isPairedDevice):
            workspacePendingContent(isPairedDevice: isPairedDevice)
        case .ready:
            readyContent
        }
    }

    private var checkingContent: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text(verbatim: "Checking your workspace…")
                .font(.headline)
                .accessibilityIdentifier("debug.auth.checkingState")
            Text(verbatim: "This is a local loading preview. No account check is running.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)

            secondaryButton("Cancel check", systemImage: "xmark") {
                app.debugShowAuthPreview(.signedOut)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("debug.auth.checkingState")
    }

    private var entryContent: some View {
        let authenticationInProgress = isAuthenticating

        return VStack(spacing: 0) {
            Text(verbatim: "Track every income")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.96))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let failureMessage {
                failureNotice(failureMessage)
                    .padding(.top, 18)
            }

            if authenticationInProgress {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(verbatim: "Opening " + (app.debugAuthPreviewProviderName ?? "your account") + "…")
                        .font(.subheadline)
                        .accessibilityIdentifier("debug.auth.authenticatingState")
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 18)
            } else {
                Text(verbatim: "Account onboarding preview")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.top, 8)
            }

            VStack(spacing: 10) {
                if authenticationInProgress {
                    primaryButton("Simulate success", systemImage: "checkmark") {
                        app.debugCompleteAuthPreview()
                    }
                    secondaryButton("Simulate error", systemImage: "exclamationmark.triangle") {
                        app.debugShowAuthPreview(.signInFailure)
                    }
                    secondaryButton("Cancel sign-in", systemImage: "xmark") {
                        app.debugShowAuthPreview(.signedOut)
                    }
                } else {
                    primaryButton("Continue with Google", systemImage: "g.circle.fill") {
                        app.debugBeginAuthenticating(provider: "Google")
                    }
                    secondaryButton("Continue with GitHub", systemImage: "chevron.left.forwardslash.chevron.right") {
                        app.debugBeginAuthenticating(provider: "GitHub")
                    }
                }
            }
            .padding(.top, 20)

            HStack(spacing: 10) {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1)
                Text(verbatim: "LOCAL-ONLY OPTIONS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize()
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1)
            }
            .padding(.vertical, 20)

            VStack(spacing: 10) {
                secondaryButton("Continue without an account", systemImage: "iphone") {
                    app.debugCompleteAuthPreview()
                }
                secondaryButton("Pair a device", systemImage: "qrcode") {
                    app.debugShowAuthPreview(.pairedWorkspacePending)
                }
            }

            Text(verbatim: "These buttons change only this preview. They do not open a provider, write a session, sync, or modify the ledger.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
        }
    }

    private func workspacePendingContent(isPairedDevice: Bool) -> some View {
        VStack(spacing: 18) {
            Image(systemName: isPairedDevice ? "qrcode" : "clock.badge.exclamationmark")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(verbatim: isPairedDevice ? "Finish pairing this device" : "Finish setting up your workspace")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier(isPairedDevice ? "debug.auth.pairedWorkspacePendingState" : "debug.auth.workspacePendingState")
                Text(verbatim: isPairedDevice
                     ? "Preview the one-time-code handoff without connecting a device."
                     : "Preview the state after identity succeeds while workspace access is still being prepared.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
            }

            primaryButton("Simulate workspace ready", systemImage: "checkmark") {
                app.debugCompleteAuthPreview()
            }
            secondaryButton("Simulate sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                app.debugShowAuthPreview(.signedOut)
            }
            secondaryButton("Show recoverable error", systemImage: "exclamationmark.triangle") {
                app.debugShowAuthPreview(.offlineFailure)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .multilineTextAlignment(.center)
    }

    private var readyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(verbatim: "Account preview complete")
                .font(.title3.weight(.semibold))
            primaryButton("Return to ledger", systemImage: "arrow.right") {
                app.debugCompleteAuthPreview()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var videoIsActive: Bool {
        switch app.accountState {
        case .signedOut, .authenticating, .failure:
            true
        case .checking, .awaitingWorkspace, .ready:
            false
        }
    }

    private var isAuthenticating: Bool {
        if case .authenticating = app.accountState { return true }
        return false
    }

    private var failureMessage: String? {
        if case let .failure(message) = app.accountState { return message }
        return nil
    }

    private func failureNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Sign-in issue")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("debug.auth.failure")
                Text(verbatim: message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.orange.opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func primaryButton(_ title: String,
                               systemImage: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
    }

    private func secondaryButton(_ title: String,
                                 systemImage: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.92))
        .background(.white.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }
}
#endif
