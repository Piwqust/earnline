import SwiftUI

/// Step 3 — "You're all set!".
///
/// Unlike the two wizard steps this draws no panel: the real ledger is right
/// behind it, now holding the client and the line the owner just made. A soft
/// scrim fades that ledger out under the copy — the same progressive-blur edge
/// the app uses at its scroll boundaries — so the result stays visible without
/// competing with the message.
struct OnboardingDoneOverlay: View {
    let clientName: String
    /// Already formatted in the owner's base currency.
    let firstAmount: String
    let start: () -> Void

    var body: some View {
        ZStack {
            scrim
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.step.done")
    }

    private var scrim: some View {
        // A material masked by the same ramp keeps the ledger legible at the
        // top and fully quiet behind the copy.
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(ramp)
            .overlay(ramp)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var ramp: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.background.opacity(0), location: 0),
                .init(color: Theme.background.opacity(0.88), location: 0.30),
                .init(color: Theme.background, location: 0.46),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Image("OnboardingComplete")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 208, height: 194)
                    .onboardingArtworkStyle()
                    .accessibilityHidden(true)

                Text("You’re all set!")
                    .appFont(32, .semibold, relativeTo: .largeTitle)
                    .tracking(-0.43)
                    .foregroundStyle(Theme.label(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(clientName) and your first \(firstAmount) earning are ready.")
                    .appFont(15, .medium, relativeTo: .subheadline)
                    .tracking(-0.43)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 222)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            PillCTA("Let’s start", action: start)
                .padding(.horizontal, 36)
                .accessibilityIdentifier("onboarding.done.primary")
        }
        .padding(.bottom, 36)
    }
}
