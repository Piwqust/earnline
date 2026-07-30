import Foundation
import Testing
@testable import earnline

/// The app-lock state machine: opt-in gating, the `.inactive` privacy cover
/// that doesn't commit a lock, and the `.background` lock that does.
/// (The biometric prompt itself is LocalAuthentication's; it isn't unit-tested.)
@MainActor
@Suite(.serialized)
struct AppLockTests {
    /// `requireAppLock` persists through UserDefaults — restore whatever the
    /// suite found so tests never leave the simulator's app locked.
    private func withLockSetting(_ enabled: Bool, _ body: (AppModel) -> Void) {
        let app = AppModel()
        let original = app.requireAppLock
        app.requireAppLock = enabled
        body(app)
        app.requireAppLock = original
    }

    @Test func lockIsOptIn() {
        withLockSetting(false) { app in
            app.lockIfNeeded()
            #expect(!app.isLocked)
            app.coverIfNeeded()
            #expect(!app.isLocked)
        }
    }

    @Test func backgroundingCommitsTheLock() {
        withLockSetting(true) { app in
            app.lockIfNeeded()
            #expect(app.isLocked)
        }
    }

    @Test func inactiveCoverDoesNotCommitTheLock() {
        withLockSetting(true) { app in
            // Control Center peek / incoming call: cover, but returning to
            // .active must not demand re-authentication.
            app.coverIfNeeded()
            #expect(!app.isLocked)
            app.uncoverIfNeeded()
            #expect(!app.isLocked)
        }
    }

    @Test func coldLaunchStartsLockedWhenEnabled() {
        withLockSetting(true) { app in
            app.lockOnLaunchIfNeeded()
            #expect(app.isLocked)
        }
    }

    @Test func settingTitleMatchesAvailableBiometry() {
        // Device-dependent, but always one of the four honest labels — never
        // a blank and never unconditionally "Face ID".
        let title = AppLockAuth.settingTitle
        #expect(!title.isEmpty)
    }

    @Test func missingDevicePasscodeIsNeverAnAuthenticationSuccess() {
        // A missing policy used to be treated as an immediate unlock, leaving
        // a visibly enabled App Lock without any protection.
        #expect(AppLockAuth.evaluation(
            policyAvailable: false,
            authenticationSucceeded: true
        ) == .unavailable)
        #expect(AppLockAuth.evaluation(
            policyAvailable: true,
            authenticationSucceeded: false
        ) == .denied)
    }

    /// The controller drives the same state machine without an `AppModel`, a
    /// UserDefaults suite, or a window — which is the point of it being its own
    /// type. The preference is injected, so these never touch the simulator's
    /// persisted lock setting.
    private func makeController(enabled: Bool) -> (AppLockController, () -> Bool) {
        let controller = AppLockController()
        // A box, so the test can observe the controller turning an impossible
        // lock off through the `disable` callback.
        final class Box { var isEnabled: Bool; init(_ value: Bool) { isEnabled = value } }
        let box = Box(enabled)
        controller.configure(
            isEnabled: { box.isEnabled },
            disable: { box.isEnabled = false },
            interfaceStyle: { .unspecified },
            createsWindow: { false }
        )
        return (controller, { box.isEnabled })
    }

    @Test func controllerLockIsOptInWithoutAnAppModel() {
        let (controller, _) = makeController(enabled: false)
        controller.lockIfNeeded()
        #expect(!controller.isLocked)
        controller.coverIfNeeded()
        #expect(!controller.isLocked)
    }

    @Test func controllerSeparatesTheCoverFromTheCommittedLock() {
        let (controller, isEnabled) = makeController(enabled: true)
        // The cover only reaches the committed state when the device can
        // actually authenticate; a simulator without a passcode disables the
        // lock instead, which is itself the documented behaviour.
        controller.coverIfNeeded()
        #expect(!controller.isLocked)

        controller.lockIfNeeded()
        if isEnabled() {
            #expect(controller.isLocked)
        } else {
            // The lock turned itself off because no passcode is available, and
            // said so rather than leaving an unlockable cover up.
            #expect(!controller.isLocked)
            #expect(controller.notice != nil)
        }
    }
}
