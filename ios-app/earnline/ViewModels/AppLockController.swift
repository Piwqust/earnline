import Observation
import SwiftUI

/// Owns the optional App Lock: the committed/uncommitted cover distinction, the
/// biometric prompt, and the alert-level window the cover lives in.
///
/// Split out of `AppModel` because this is the one place in the app model that
/// reached for UIKit directly — creating, keying, and tearing down a `UIWindow`.
/// Keeping it here leaves `AppModel` free of window management, and lets the
/// lock's state machine be reasoned about (and tested) without the rest of the
/// app's currency, workspace, and sync state around it.
///
/// The `AppLockAuth` policy itself stays where it was; this only sequences it.
@MainActor
@Observable
final class AppLockController {
    /// Whether the lock is *committed* — set on backgrounding, cleared only by a
    /// successful authentication. A privacy cover shown on `.inactive` is not
    /// this: see `cover()`.
    private(set) var isLocked = false

    /// A non-blocking privacy message shown in Settings after the app disables
    /// an impossible legacy lock (for example, after the device passcode was
    /// removed). The ledger is never left behind a cover it cannot unlock.
    var notice: String?

    /// Whether the owner has asked for the lock. Persisted by `AppModel`, which
    /// keeps every UserDefaults key in one place; this controller reads and
    /// clears it through these callbacks.
    @ObservationIgnored private var isEnabled: () -> Bool = { false }
    @ObservationIgnored private var disable: () -> Void = {}
    /// Appearance for the lock window at creation time, so the cover never
    /// flashes in the system scheme when the app is overriding it. Later changes
    /// arrive through `AppModel.applyAppearance()`, which walks every window in
    /// the scene — this one included.
    @ObservationIgnored private var interfaceStyle: () -> UIUserInterfaceStyle = { .unspecified }
    /// Swift Testing exercises this state machine directly, but its ephemeral
    /// host window never receives a full scene appearance cycle. Creating a
    /// second alert-level window there produces UIKit's spurious
    /// unbalanced-transition warning.
    @ObservationIgnored private var createsWindow: () -> Bool = { true }

    @ObservationIgnored private var lockWindow: UIWindow?
    @ObservationIgnored private var isUnlocking = false

    init() {}

    /// Wired by `AppModel` once its persisted preferences exist.
    func configure(
        isEnabled: @escaping () -> Bool,
        disable: @escaping () -> Void,
        interfaceStyle: @escaping () -> UIUserInterfaceStyle,
        createsWindow: @escaping () -> Bool
    ) {
        self.isEnabled = isEnabled
        self.disable = disable
        self.interfaceStyle = interfaceStyle
        self.createsWindow = createsWindow
    }

    /// Cold launches start covered when the lock is on; the biometric prompt
    /// fires as soon as the window exists (called from the root `.task`).
    func lockOnLaunchIfNeeded() {
        guard canUseAppLock else { return }
        isLocked = true
        showLockWindow()
        attemptUnlockIfNeeded()
    }

    /// Called on backgrounding — covers the content before the app-switcher
    /// snapshot is taken, so amounts never show in the multitasking UI.
    func lockIfNeeded() {
        guard canUseAppLock, !isLocked else { return }
        isLocked = true
        showLockWindow()
    }

    /// Called on `.inactive` — the app-switcher snapshot is taken while the
    /// scene is still inactive, before `.background` fires, so waiting for
    /// backgrounding briefly exposed the ledger in the multitasking UI. This
    /// shows the cover *without* committing the lock: swiping away Control
    /// Center or an incoming-call banner returns straight to content, no
    /// re-authentication.
    func coverIfNeeded() {
        guard canUseAppLock, !isLocked else { return }
        showLockWindow()
    }

    /// Called on `.active` — removes an uncommitted privacy cover. A real
    /// lock (set on `.background`) stays up until `attemptUnlockIfNeeded`
    /// succeeds.
    func uncoverIfNeeded() {
        guard !isLocked else { return }
        hideLockWindow()
    }

    /// Called on activation and by the lock screen's Unlock button.
    func attemptUnlockIfNeeded() {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch await AppLockAuth.evaluate(reason: String(localized: "Unlock your income ledger")) {
            case .authenticated:
                self.isLocked = false
                self.hideLockWindow()
            case .unavailable:
                self.disableUnavailableAppLock()
                self.isLocked = false
                self.hideLockWindow()
            case .denied:
                break
            }
            self.isUnlocking = false
        }
    }

    private var canUseAppLock: Bool {
        guard isEnabled() else { return false }
        guard AppLockAuth.isAuthenticationAvailable else {
            disableUnavailableAppLock()
            return false
        }
        return true
    }

    private func disableUnavailableAppLock() {
        guard isEnabled() else { return }
        disable()
        notice = String(localized: "App Lock was turned off because this iPhone no longer has a device passcode.")
    }

    /// The lock lives in its own alert-level window for the same reason dark
    /// mode is a window-level override: a SwiftUI overlay in the root view
    /// sits *under* presented sheets, and the lock must cover those too.
    private func showLockWindow() {
        guard createsWindow() else { return }
        guard lockWindow == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState != .unattached }) ?? scenes.first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = interfaceStyle()
        window.rootViewController = UIHostingController(
            rootView: LockScreenView { [weak self] in self?.attemptUnlockIfNeeded() }
        )
        window.makeKeyAndVisible()
        lockWindow = window
    }

    private func hideLockWindow() {
        guard let window = lockWindow else { return }
        // Tear the alert-level window down in UIKit's expected order. Leaving
        // its hosting controller attached while dropping the last window
        // reference produced unbalanced appearance transitions in tests and
        // could leave the main scene without a key window after unlock.
        window.resignKey()
        window.isHidden = true
        window.rootViewController = nil
        lockWindow = nil
    }
}
