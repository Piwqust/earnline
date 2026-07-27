#if DEBUGMENU
import SwiftData
import SwiftUI
import UIKit

// This file only exists in the `earnline-dev` target (the DEBUGMENU
// compilation condition in project.yml). The App Store target compiles it to
// nothing, so every string here stays verbatim-English and out of the
// localization catalog on purpose.

// MARK: - Global access (floating chip + shake)

/// The debug menu is reachable from ANY screen — the gate, the ledger, or
/// over an open sheet — via its own passthrough window above the app (the
/// same technique as the App Lock cover, one level below it so the privacy
/// cover always wins). A floating glass chip on the trailing edge opens the
/// menu; drag it vertically if it covers something, and shake the device
/// (⌃⌘Z in the simulator) to open the menu without the chip.
@MainActor
enum DebugMenuOverlay {
    private static var window: PassthroughWindow?

    /// Called by the host whenever the active SwiftData container changes so
    /// the menu always seeds/wipes the store the app is actually showing.
    static func install(app: AppModel, container: ModelContainer) {
        if window == nil {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState != .unattached }) ?? scenes.first else { return }
            let overlay = PassthroughWindow(windowScene: scene)
            // Below the App Lock window (.alert + 1): the cover must hide
            // even debug chrome.
            overlay.windowLevel = .alert
            overlay.isHidden = false
            window = overlay
        }
        let host = UIHostingController(rootView: DebugOverlayRoot(app: app, container: container))
        host.view.backgroundColor = .clear
        window?.rootViewController = host
    }

    /// Only touches that land on the chip (or the presented menu) are
    /// consumed; everywhere else the window is invisible to hit-testing.
    /// SwiftUI renders its controls inside one hosting view, so "which
    /// subview was hit" can't distinguish the chip from empty space — the
    /// root view publishes the chip's frame instead and the window tests
    /// against that.
    private final class PassthroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // While the menu sheet is up, behave like a normal window.
            if rootViewController?.presentedViewController != nil {
                return super.hitTest(point, with: event)
            }
            guard DebugOverlayHitRegions.shared.contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}

/// The chip reports its on-screen frame here; the passthrough window consults
/// it on every touch.
@MainActor
final class DebugOverlayHitRegions {
    static let shared = DebugOverlayHitRegions()
    var frames: [CGRect] = []

    func contains(_ point: CGPoint) -> Bool {
        frames.contains { $0.insetBy(dx: -8, dy: -8).contains(point) }
    }
}

extension Notification.Name {
    static let earnlineDebugShake = Notification.Name("earnlineDebugShake")
}

extension UIWindow {
    /// UIResponder's default does nothing, so providing the override in an
    /// extension is safe; every key window in the dev build reports shakes.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .earnlineDebugShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

private struct DebugOverlayRoot: View {
    let app: AppModel
    let container: ModelContainer

    @State private var showingMenu = false
    /// Normalized vertical position of the chip along the trailing edge.
    /// Defaults to the quiet zone below the hero/summary, clear of the
    /// gate's docked buttons and the ledger's bottom bar; drag to move.
    @State private var chipPosition: CGFloat = 0.42
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            chip
                .position(
                    x: proxy.size.width - 34,
                    y: (chipPosition * proxy.size.height + dragTranslation)
                        .clamped(to: 80 ... (proxy.size.height - 80))
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragTranslation = value.translation.height
                        }
                        .onEnded { value in
                            let landed = chipPosition * proxy.size.height + value.translation.height
                            chipPosition = (landed / proxy.size.height).clamped(to: 0.1 ... 0.9)
                            dragTranslation = 0
                        }
                )
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingMenu) {
            DebugMenuView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .earnlineDebugShake)) { _ in
            showingMenu = true
        }
        .environment(app)
        .modelContainer(container)
    }

    private var chip: some View {
        Button {
            showingMenu = true
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(verbatim: "Debug menu"))
        .accessibilityIdentifier("debug.chip")
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            DebugOverlayHitRegions.shared.frames = [frame]
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Menu

/// The dev-build control room: seed or wipe the local store and read the flags
/// and identities that normally require a debugger to see. Every row explains
/// what it does.
struct DebugMenuView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var actionNote: String?
    @State private var flagsNote: String?
    @State private var onboardingNote: String?
    @State private var confirmingWipe = false
    @State private var confirmingCrash = false

    var body: some View {
        Form {
            authenticationSection
            onboardingSection
            dataSection
            flagsSection
            systemSection
            diagnosticsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .sheetHeader("Debug", onClose: { dismiss() })
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .confirmationDialog(Text(verbatim: "Wipe the local store?"),
                            isPresented: $confirmingWipe,
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                wipeLocalStore()
            } label: {
                Text(verbatim: "Wipe local store")
            }
        } message: {
            Text(verbatim: "Deletes every client, entry, heading, tombstone, and icon preference from the CURRENT local container only. The server is not touched; a later sync pulls server rows back.")
        }
        .confirmationDialog(Text(verbatim: "Crash the app?"),
                            isPresented: $confirmingCrash,
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                fatalError("Debug menu: forced crash for testing crash handling.")
            } label: {
                Text(verbatim: "Crash now")
            }
        } message: {
            Text(verbatim: "Calls fatalError() so you can exercise crash reporting and relaunch behavior.")
        }
    }

    // MARK: Account and onboarding

    private var authenticationSection: some View {
        Section {
            ForEach(AppModel.DebugAuthPreview.allCases) { preview in
                actionRow(
                    preview.title,
                    preview.caption,
                    accessibilityIdentifier: preview.accessibilityIdentifier
                ) {
                    dismiss()
                    app.debugShowAuthPreview(preview)
                }
            }
            actionRow(
                "Simulate sign out",
                "Returns to the signed-out account screen without removing a real credential or changing this device’s local ledger.",
                accessibilityIdentifier: "debug.auth.signOut"
            ) {
                dismiss()
                app.debugShowAuthPreview(.signedOut)
            }
            actionRow(
                "Return to ledger",
                "Closes any local account preview and restores the account state that was active before testing.",
                accessibilityIdentifier: "debug.auth.returnToLedger"
            ) {
                dismiss()
                app.debugCompleteAuthPreview()
            }
        } header: {
            Text(verbatim: "Account")
        } footer: {
            Text(verbatim: "Every scenario is local to earnline Dev: no OAuth sheet, Supabase request, session change, or ledger data change occurs. These are the account screens only — the first-run flow lives in its own section below.")
        }
    }

    /// The first-run flow. Separate from the account previews above: it is a
    /// real, writing flow rather than a visual state, so replaying it adds a
    /// client and a line to whatever container is on screen.
    private var onboardingSection: some View {
        Section {
            actionRow(
                "Replay onboarding",
                "Shows the two-step first-run flow over the current ledger. It creates a real client and a real line — it is not a mock.",
                accessibilityIdentifier: "debug.onboarding.replay"
            ) {
                dismiss()
                app.isPresentingOnboarding = true
            }
            actionRow(
                "Reset onboarding flag",
                "Marks this workspace as never introduced, so the next cold launch opens the flow on its own. Existing clients and lines are left alone.",
                accessibilityIdentifier: "debug.onboarding.reset"
            ) {
                app.onboardingCompleted = false
                onboardingNote = "Onboarding will run on the next launch."
            }
        } header: {
            Text(verbatim: "Onboarding")
        } footer: {
            if let onboardingNote {
                Text(verbatim: onboardingNote)
            } else {
                Text(verbatim: "The flag is stored per workspace, so Production and Test each get their own introduction.")
            }
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            actionRow("Seed sample ledger",
                      "Inserts the small demo notebook a fresh install starts with (clients, entries, headings).") {
                SampleData.seed(context)
                save(note: "Seeded the sample ledger.")
            }
            actionRow("Seed insights demo ledger",
                      "Deterministic multi-month earnings history — the fixture the Insights charts are designed against.") {
                let count = SampleData.seedGenerated(context)
                save(note: "Seeded \(count) generated insights entries.")
            }
            actionRow("Seed stress ledger",
                      "Thousands of entries across many months for scroll and launch performance testing.") {
                let count = SampleData.seedStress(context)
                save(note: "Seeded \(count) stress entries.")
            }
            actionRow("Wipe local store…",
                      "Deletes every row from the current local container after a confirmation. Server data is untouched.",
                      role: .destructive) {
                confirmingWipe = true
            }
        } header: {
            Text(verbatim: "Data (current container)")
        } footer: {
            if let actionNote {
                Text(verbatim: actionNote)
            }
        }
    }

    // MARK: Flags

    private var flagsSection: some View {
        Section {
            actionRow("Reset Developer Mode",
                      "Switches the Developer Mode toggle off, hiding the advanced Settings sections again.") {
                app.developerModeEnabled = false
                flagsNote = "Developer Mode switched off."
            }
            actionRow("Reset experimental features",
                      "Turns every Experimental toggle (client badges) back off. Project icons and Onboarding are routes rather than toggles — use the Onboarding section above to replay or re-arm the first run.") {
                app.clientBadgesEnabled = false
                flagsNote = "Experimental features reset."
            }
        } header: {
            Text(verbatim: "Flags")
        } footer: {
            if let flagsNote {
                Text(verbatim: flagsNote)
            }
        }
    }

    // MARK: System

    private var systemSection: some View {
        Section {
            actionRow("Sync now",
                      "Runs one full sync of the current workspace immediately. Does nothing while signed out or in guest mode.") {
                Task { await app.syncNow(context: context) }
            }
            actionRow("Lock now",
                      "Shows the App Lock cover immediately. Requires App Lock to be enabled in Settings, otherwise the row is disabled.") {
                app.lockIfNeeded()
            }
            .disabled(!app.requireAppLock)
            actionRow("Crash (test)…",
                      "Calls fatalError() after a confirmation, to exercise crash reporting and relaunch behavior.",
                      role: .destructive) {
                confirmingCrash = true
            }
        } header: {
            Text(verbatim: "System")
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        Section {
            diagnosticRow("Bundle", Bundle.main.bundleIdentifier ?? "?")
            diagnosticRow("Version", "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
            diagnosticRow("Environment", app.workspaceEnvironment.rawValue)
            diagnosticRow("Workspace ID", app.workspaceID)
            diagnosticRow("Store identity", app.workspaceStoreIdentity)
            diagnosticRow("Account state", app.debugAccountStateDescription)
            diagnosticRow("Sync message", app.syncMessage)
            diagnosticRow("Guest flag", app.defaults.bool(forKey: AppModel.localGuestDefaultsKey) ? "on" : "off")
            diagnosticRow("Developer Mode", app.developerModeEnabled ? "on" : "off")
        } header: {
            Text(verbatim: "Diagnostics")
        } footer: {
            Text(verbatim: "Live values, selectable for copying. Open from anywhere: tap the floating ladybug chip (drag it if it covers something) or shake the device — ⌃⌘Z in the simulator.")
        }
    }

    // MARK: Building blocks

    private func actionRow(_ title: String,
                           _ caption: String,
                           role: ButtonRole? = nil,
                           accessibilityIdentifier: String? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                Text(verbatim: caption)
                    .font(.footnote)
                    // Concrete color: `.secondary` inside a Button resolves
                    // against the accent tint, not the label.
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.footnote)
    }

    private func save(note: String) {
        do {
            try context.save()
            actionNote = note
        } catch {
            actionNote = "Save failed: \(error.localizedDescription)"
        }
    }

    private func wipeLocalStore() {
        do {
            // Children before Client so relationship cascades cannot trip on
            // already-deleted rows; batch deletes create no sync tombstones,
            // which keeps this wipe strictly local.
            try context.delete(model: Entry.self)
            try context.delete(model: Heading.self)
            try context.delete(model: SyncTombstone.self)
            try context.delete(model: ProjectIconPreference.self)
            try context.delete(model: Client.self)
            try context.save()
            actionNote = "Local store wiped."
        } catch {
            actionNote = "Wipe failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Debug-only model helpers

extension AppModel {
    /// All account previews are visual-only. They are deliberately separate
    /// from `AccountState` so a Dev build cannot accidentally exercise a real
    /// provider, alter the stored Supabase session, or switch a workspace.
    enum DebugAuthPreview: String, CaseIterable, Identifiable {
        case signedOut
        case checking
        case signingIn
        case signInFailure
        case offlineFailure
        case workspacePending
        case pairedWorkspacePending

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signedOut: "Open the signed-out account screen"
            case .checking: "Show account check"
            case .signingIn: "Show sign-in in progress"
            case .signInFailure: "Show sign-in error"
            case .offlineFailure: "Show offline sign-in error"
            case .workspacePending: "Show workspace pending"
            case .pairedWorkspacePending: "Show paired-device setup"
            }
        }

        var caption: String {
            switch self {
            case .signedOut:
                "The signed-out account screen, including the onboarding video and local entry options."
            case .checking:
                "The minimal loading state while an existing account is being checked."
            case .signingIn:
                "A provider action in progress; use the preview controls to finish, cancel, or fail it."
            case .signInFailure:
                "A recoverable authentication failure above the usual entry actions."
            case .offlineFailure:
                "The account screen when the sign-in request cannot reach the network."
            case .workspacePending:
                "The state after identity succeeds but the workspace is not ready yet."
            case .pairedWorkspacePending:
                "The matching setup state for a device linked by a one-time pairing code."
            }
        }

        var accessibilityIdentifier: String { "debug.auth.\(rawValue)" }
    }

    func debugShowAuthPreview(_ preview: DebugAuthPreview) {
        if !debugAuthGatePreview {
            debugAccountStateBeforePreview = accountState
        }

        showSettings = false
        debugAuthGatePreview = true
        debugAuthPreviewProviderName = nil

        switch preview {
        case .signedOut:
            accountState = .signedOut
        case .checking:
            accountState = .checking
        case .signingIn:
            debugAuthPreviewProviderName = "Google"
            accountState = .authenticating
        case .signInFailure:
            accountState = .failure("We couldn’t complete the sign-in. Try again or choose a different method.")
        case .offlineFailure:
            accountState = .failure("You appear to be offline. Reconnect and try signing in again.")
        case .workspacePending:
            accountState = .awaitingWorkspace(isPairedDevice: false)
        case .pairedWorkspacePending:
            accountState = .awaitingWorkspace(isPairedDevice: true)
        }
    }

    func debugBeginAuthenticating(provider: String) {
        guard isDebugAuthGatePreview else { return }
        debugAuthPreviewProviderName = provider
        accountState = .authenticating
    }

    func debugCompleteAuthPreview() {
        guard isDebugAuthGatePreview else { return }
        accountState = debugAccountStateBeforePreview
            ?? .ready(AccountSession(
                userID: "debug-local",
                email: nil,
                workspaceID: workspaceID,
                membershipRole: "owner",
                isPairedDevice: false,
                isLocalOnly: true
            ))
        debugAccountStateBeforePreview = nil
        debugAuthPreviewProviderName = nil
        debugAuthGatePreview = false
    }

    var debugAccountStateDescription: String {
        switch accountState {
        case .checking: "checking"
        case .signedOut: "signedOut"
        case .authenticating: "authenticating"
        case let .awaitingWorkspace(paired): "awaitingWorkspace(paired: \(paired))"
        case let .ready(session): "ready(\(session.isLocalOnly ? "local" : session.isPairedDevice ? "paired" : "owner"))"
        case let .failure(message): "failure(\(message))"
        }
    }

}
#endif
