import SwiftUI
import LocalAuthentication

/// Biometric gate for the optional app lock. `.deviceOwnerAuthentication`
/// includes the passcode fallback, so enabling the lock can never strand the
/// user on a device without (working) Face ID.
enum AppLockAuth {
    static func evaluate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode and no biometrics enrolled — there is nothing to
            // authenticate against, so a hard lock would strand the user on
            // the cover screen forever. Unlock: a device without a passcode
            // offers no OS-level data protection for the lock to extend.
            return error?.code == LAError.passcodeNotSet.rawValue
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: reason)) ?? false
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
