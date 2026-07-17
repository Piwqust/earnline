import SwiftUI

/// The guided first-entry tour: after the auth gate hands off to an empty
/// ledger, three spotlight steps walk the user through actually writing
/// their first line — compose it, set its status, read the summary cards.
/// Runs once per install (guests and accounts alike), skippable at every
/// step, and never shows again after completion or skip.
///
/// Anatomy: targets in the ledger publish their bounds through
/// `tourAnchor(_:)`; `FirstRunTourOverlay` dims everything around the active
/// target with four opaque strips — a real hole, so the spotlighted control
/// stays fully interactive — and floats a callout card with the step copy.

// MARK: - State machine

@Observable @MainActor
final class FirstRunTourState {
    enum Step: Int, Equatable {
        case compose, status, summary
    }

    private(set) var step: Step?
    private var evaluated = false

    /// Called once the first ledger snapshot lands. Starts the tour only on
    /// a genuinely empty ledger; an already-populated ledger (an existing
    /// user updating the app) completes the tour silently so it never fires
    /// on a later empty month.
    func evaluateStart(app: AppModel, hasAnyEntries: Bool) {
        if app.debugForceFirstRunTour {
            app.debugForceFirstRunTour = false
            evaluated = true
            step = .compose
            return
        }
        guard !evaluated, step == nil, app.shouldOfferFirstRunTour else { return }
        evaluated = true
        if hasAnyEntries {
            app.hasCompletedFirstRunTour = true
        } else {
            step = .compose
        }
    }

    /// The compose step completes itself when the first entry actually lands
    /// in the store — robust against every insertion path (composer, paste).
    func entrySaved(hasAnyEntries: Bool) {
        guard step == .compose, hasAnyEntries else { return }
        step = .status
    }

    func advance(app: AppModel) {
        switch step {
        case .compose: step = .status
        case .status: step = .summary
        case .summary: complete(app: app)
        case nil: break
        }
    }

    func skip(app: AppModel) {
        complete(app: app)
    }

    private func complete(app: AppModel) {
        step = nil
        app.hasCompletedFirstRunTour = true
    }
}

// MARK: - Anchors

enum FirstRunTourTarget: Hashable {
    case emptyStateCTA, composer, entryStatus, summaryCards
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [FirstRunTourTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [FirstRunTourTarget: Anchor<CGRect>],
                       nextValue: () -> [FirstRunTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's bounds as a tour spotlight target. Passing nil
    /// leaves the view untouched, so call sites can anchor conditionally.
    @ViewBuilder
    func tourAnchor(_ target: FirstRunTourTarget?) -> some View {
        if let target {
            anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
        } else {
            self
        }
    }
}

// MARK: - Overlay

struct FirstRunTourOverlay: View {
    @Environment(AppModel.self) private var app
    @AccessibilityFocusState private var calloutFocused: Bool

    let tour: FirstRunTourState
    let anchors: [FirstRunTourTarget: Anchor<CGRect>]

    var body: some View {
        if let step = tour.step {
            GeometryReader { proxy in
                let cutout = cutoutRect(for: step, in: proxy)
                ZStack(alignment: .topLeading) {
                    if let cutout {
                        dimStrips(around: cutout, in: proxy.size)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: cutout.width, height: cutout.height)
                            .offset(x: cutout.minX, y: cutout.minY)
                            .shadow(color: .black.opacity(0.35), radius: 12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    callout(for: step, cutout: cutout, in: proxy.size)
                }
                .animation(.smooth(duration: 0.3), value: cutout)
            }
            .ignoresSafeArea(.keyboard)
            .transition(.opacity)
            .onAppear { calloutFocused = true }
            .onChange(of: step) { _, _ in calloutFocused = true }
        }
    }

    // MARK: Geometry

    /// The compose step prefers the live composer row and falls back to the
    /// empty-state CTA that opens it. A missing anchor (scrolled away, or a
    /// debug replay on a populated ledger) drops the dim entirely and keeps
    /// just the floating callout, so nothing gets blocked.
    private func cutoutRect(for step: FirstRunTourState.Step,
                            in proxy: GeometryProxy) -> CGRect? {
        let anchor: Anchor<CGRect>? = switch step {
        case .compose: anchors[.composer] ?? anchors[.emptyStateCTA]
        case .status: anchors[.entryStatus]
        case .summary: anchors[.summaryCards]
        }
        guard let anchor else { return nil }
        return proxy[anchor].insetBy(dx: -6, dy: -6)
    }

    /// Four opaque strips around the cutout: they absorb every touch while
    /// the hole between them stays genuinely empty and interactive.
    @ViewBuilder
    private func dimStrips(around cutout: CGRect, in size: CGSize) -> some View {
        let dim = Color.black.opacity(0.45)
        Group {
            dim.frame(width: size.width, height: max(cutout.minY, 0))
                .offset(x: 0, y: 0)
            dim.frame(width: size.width, height: max(size.height - cutout.maxY, 0))
                .offset(x: 0, y: cutout.maxY)
            dim.frame(width: max(cutout.minX, 0), height: cutout.height)
                .offset(x: 0, y: cutout.minY)
            dim.frame(width: max(size.width - cutout.maxX, 0), height: cutout.height)
                .offset(x: cutout.maxX, y: cutout.minY)
        }
        .accessibilityHidden(true)
    }

    // MARK: Callout

    private func callout(for step: FirstRunTourState.Step,
                         cutout: CGRect?,
                         in size: CGSize) -> some View {
        // Below the target when it sits in the upper half, above it otherwise;
        // near the bottom when there is no target.
        let placesBelow = (cutout?.midY ?? size.height) < size.height / 2
        let topInset: CGFloat = placesBelow ? (cutout.map { $0.maxY + 12 } ?? 0) : 0
        let bottomInset: CGFloat
        if placesBelow {
            bottomInset = 0
        } else if let cutout {
            bottomInset = max(size.height - cutout.minY + 12, 12)
        } else {
            bottomInset = size.height / 3
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text(title(for: step))
                .appFont(17, .semibold)
                .foregroundStyle(.white)
            Text(message(for: step))
                .appFont(15)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip") { tour.skip(app: app) }
                    .appFont(15, .medium)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityIdentifier("tour.skip")

                Spacer(minLength: 24)

                switch step {
                case .compose:
                    EmptyView()
                case .status:
                    Button("Next") { tour.advance(app: app) }
                        .appFont(15, .semibold)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("tour.next")
                case .summary:
                    Button("Done") { tour.advance(app: app) }
                        .appFont(15, .semibold)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("tour.done")
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(Color(hex: "#000003").opacity(0.94),
                    in: .rect(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: placesBelow ? .top : .bottom)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.overlay")
        .accessibilityFocused($calloutFocused)
        .accessibilitySortPriority(1)
    }

    private func title(for step: FirstRunTourState.Step) -> LocalizedStringKey {
        switch step {
        case .compose: "Write your first line"
        case .status: "Every line has a status"
        case .summary: "Your month at a glance"
        }
    }

    private func message(for step: FirstRunTourState.Step) -> LocalizedStringKey {
        switch step {
        case .compose:
            anchors[.composer] != nil
                ? "Type the amount, then the project and task — and submit it."
                : "Start here — add who pays you, then write your first income line."
        case .status:
            "The dot on the right marks a line paid, in progress, or canceled — or holds it until a date."
        case .summary:
            "Everything you earn this month adds up here. Tap Stats for charts and insights."
        }
    }
}
