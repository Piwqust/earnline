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

/// The dev-build control room: force any auth-gate state, replay onboarding
/// moments, seed or wipe the local store, and read the flags and identities
/// that normally require a debugger to see. Every row explains what it does.
struct DebugMenuView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var actionNote: String?
    @State private var flagsNote: String?
    @State private var confirmingWipe = false
    @State private var confirmingCrash = false

    var body: some View {
        Form {
            gateSection
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

    // MARK: Auth gate

    private var gateSection: some View {
        Section {
            ForEach(AppModel.DebugGateState.allCases) { preset in
                actionRow(preset.title, preset.caption) {
                    dismiss()
                    app.debugForceGateState(preset)
                }
            }
        } header: {
            Text(verbatim: "Auth gate states")
        } footer: {
            Text(verbatim: "Each row forces the account state and closes this menu so the gate is visible. Real sign-in still works from a forced gate.")
        }
    }

    private var onboardingSection: some View {
        Section {
            actionRow("Replay first-run tour",
                      "Closes this menu and replays the guided first-entry tour on the current ledger, even if it already has rows.") {
                dismiss()
                app.debugReplayFirstRunTour()
            }
        } header: {
            Text(verbatim: "Onboarding")
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
            actionRow("Clear guest-mode flag",
                      "Forgets “Continue without an account”: the next launch boots to the sign-in gate. The guest ledger stays on disk.") {
                app.defaults.removeObject(forKey: AppModel.localGuestDefaultsKey)
                flagsNote = "Guest-mode flag cleared."
            }
            actionRow("Reset Developer Mode",
                      "Switches the Developer Mode toggle off, hiding the advanced Settings sections again.") {
                app.developerModeEnabled = false
                flagsNote = "Developer Mode switched off."
            }
            actionRow("Reset experimental features",
                      "Turns every Experimental toggle (client badges) back off.") {
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
    enum DebugGateState: String, CaseIterable, Identifiable {
        case signedOut, checking, authenticating, failure, workspacePending, pairedWorkspacePending, ready

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signedOut: "Signed out"
            case .checking: "Checking"
            case .authenticating: "Authenticating"
            case .failure: "Failure"
            case .workspacePending: "Workspace pending"
            case .pairedWorkspacePending: "Workspace pending (paired)"
            case .ready: "Ready (debug session)"
            }
        }

        var caption: String {
            switch self {
            case .signedOut: "Live ledger preview behind the black panel: Apple pill, Google/GitHub icon pills, local-only options."
            case .checking: "Preview with the panel in its minimal checking state — no splash."
            case .authenticating: "Panel with all options disabled and Google's pill showing its in-flight spinner."
            case .failure: "Panel with the “Sign-in issue” notice above the buttons."
            case .workspacePending: "Panel variant a permanent account sees before the operator handoff."
            case .pairedWorkspacePending: "The same panel for a QR-paired device, with the extra pairing button."
            case .ready: "Straight to the ledger under a local-only debug session that never syncs."
            }
        }
    }

    func debugForceGateState(_ preset: DebugGateState) {
        showSettings = false
        switch preset {
        case .signedOut: accountState = .signedOut
        case .checking: accountState = .checking
        case .authenticating: accountState = .authenticating
        case .failure: accountState = .failure("Forced from the debug menu.")
        case .workspacePending: accountState = .awaitingWorkspace(isPairedDevice: false)
        case .pairedWorkspacePending: accountState = .awaitingWorkspace(isPairedDevice: true)
        case .ready: accountState = .ready(debugLocalSession())
        }
    }

    /// Clears the completion flag and forces the tour past its empty-ledger
    /// gate, so it can be replayed on a populated dev ledger.
    func debugReplayFirstRunTour() {
        showSettings = false
        hasCompletedFirstRunTour = false
        debugForceFirstRunTour = true
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

    /// Marked local-only so a forced "ready" can never let sync run against a
    /// half-real identity.
    private func debugLocalSession() -> AccountSession {
        AccountSession(
            userID: "debug",
            email: "debug@earnline.dev",
            workspaceID: workspaceID,
            membershipRole: "owner",
            isPairedDevice: false,
            isLocalOnly: true
        )
    }
}
#endif
