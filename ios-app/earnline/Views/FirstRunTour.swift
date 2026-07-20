import SwiftUI

/// One just-in-time nudge after a person reaches their empty ledger. The
/// account screen has already shown the wider product tour, so the ledger only
/// needs to help with the first real action and then disappear for good.
@Observable @MainActor
final class FirstRunTourState {
    private(set) var isPresented = false
    private var evaluated = false

    /// Called once the first ledger snapshot lands. Existing people never see
    /// the nudge after an update, even if they later visit an empty month.
    func evaluateStart(app: AppModel, hasAnyEntries: Bool) {
        if app.debugForceFirstRunTour {
            app.debugForceFirstRunTour = false
            evaluated = true
            isPresented = true
            return
        }
        guard !evaluated, !isPresented, app.shouldOfferFirstRunTour else { return }
        evaluated = true
        if hasAnyEntries {
            app.hasCompletedFirstRunTour = true
        } else {
            isPresented = true
        }
    }

    /// Saving through the composer, paste flow, or any future insertion path
    /// completes the only remaining onboarding task automatically.
    func entrySaved(app: AppModel, hasAnyEntries: Bool) {
        guard isPresented, hasAnyEntries else { return }
        complete(app: app)
    }

    func skip(app: AppModel) {
        complete(app: app)
    }

    private func complete(app: AppModel) {
        isPresented = false
        app.hasCompletedFirstRunTour = true
    }
}

// MARK: - Anchors

enum FirstRunTourTarget: Hashable {
    case emptyStateCTA
    case composer
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [FirstRunTourTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [FirstRunTourTarget: Anchor<CGRect>],
                       nextValue: () -> [FirstRunTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's bounds as a spotlight target. Passing nil leaves
    /// the live view completely untouched.
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
        if tour.isPresented {
            GeometryReader { proxy in
                let cutout = cutoutRect(in: proxy)
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
                    callout(cutout: cutout, in: proxy.size)
                }
                .animation(.smooth(duration: 0.3), value: cutout)
            }
            .ignoresSafeArea(.keyboard)
            .transition(.opacity)
            .onAppear { calloutFocused = true }
            .onChange(of: tour.isPresented) { _, presented in
                if presented { calloutFocused = true }
            }
        }
    }

    private func cutoutRect(in proxy: GeometryProxy) -> CGRect? {
        guard let anchor = anchors[.composer] ?? anchors[.emptyStateCTA] else { return nil }
        return proxy[anchor].insetBy(dx: -6, dy: -6)
    }

    /// Four opaque strips absorb input while the highlighted control remains
    /// genuinely tappable through the centre hole.
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

    private func callout(cutout: CGRect?, in size: CGSize) -> some View {
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

        return VStack(alignment: .leading, spacing: 8) {
            Text("Add your first income")
                .appFont(17, .semibold)
                .foregroundStyle(.white)
            Text(anchors[.composer] != nil
                 ? "Type the amount, then the project and task — and submit it."
                 : "Start here — add who pays you, then write your first income line.")
                .appFont(15)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Skip") { tour.skip(app: app) }
                    .appFont(15, .medium)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("tour.skip")
            }
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
}
