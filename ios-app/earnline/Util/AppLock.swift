import SwiftUI
import LocalAuthentication

/// Biometric gate for the optional app lock. `.deviceOwnerAuthentication`
/// includes the passcode fallback, so enabling the lock can never strand the
/// user on a device without (working) Face ID.
enum AppLockAuth {
    enum Evaluation: Equatable {
        case authenticated
        case unavailable
        case denied
    }

    /// A device passcode is the required fallback for the optional app lock.
    /// Never treat a missing passcode as a successful authentication: doing so
    /// would let the lock look enabled while offering no protection at all.
    static var isAuthenticationAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static let unavailableMessage = String(localized: "Set a device passcode before turning on App Lock.")

    /// Kept separate from LocalAuthentication so the security invariant is
    /// regression-testable without trying to mutate a simulator's passcode.
    static func evaluation(
        policyAvailable: Bool,
        authenticationSucceeded: Bool
    ) -> Evaluation {
        guard policyAvailable else { return .unavailable }
        return authenticationSucceeded ? .authenticated : .denied
    }

    static func evaluate(reason: String) async -> Evaluation {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return evaluation(policyAvailable: false, authenticationSucceeded: false)
        }
        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return evaluation(policyAvailable: true, authenticationSucceeded: authenticated)
        } catch {
            // Cancellation, lockout, and a failed passcode are all normal
            // denial states. The caller keeps the cover in place and lets the
            // user retry through LocalAuthentication's native path.
            return .denied
        }
    }

    /// Settings toggle title matching what the device actually offers —
    /// "Require Face ID" on a Touch ID iPhone mislabels the feature.
    static var settingTitle: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return String(localized: "Require Face ID")
        case .touchID: return String(localized: "Require Touch ID")
        case .opticID: return String(localized: "Require Optic ID")
        default: return String(localized: "Require Passcode")
        }
    }
}

/// Full-screen cover hosted in its own alert-level window (see
/// `AppModel.showLockWindow`) so it sits above any open sheets and alerts —
/// the same reasoning as the window-level dark-mode override. Deliberately
/// plain: background, mark, one button.
struct LockScreenView: View {
    var onUnlock: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular, in: .circle)
                Text("earnline is locked")
                    .appFont(17, .semibold)
                    .foregroundStyle(Theme.label)
                Button(action: onUnlock) {
                    Text("Unlock")
                        .appFont(16, .medium)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}
