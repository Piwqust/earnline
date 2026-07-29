import SwiftUI

// Shared chrome for the two wizard steps: the step rule, the wordmark, the
// two-tone title, and the bottom panel they sit above.
//
// Every metric here is the Figma value (node `471:4904`). The colors are
// `Theme` tokens rather than the literal light-mode hexes the Figma carries,
// so the flow follows the app's Light/Dark setting — `Theme.background`
// already *is* the Figma `#F2F2F7`, and `Theme.label` already *is* `#1A1A1A`.

// MARK: - Step header

/// The rule + "Step 1 / Step 2" pair, the wordmark, and the title, centered
/// under the status bar.
struct OnboardingStepHeader: View {
    /// Zero-based index of the step being shown.
    let step: Int
    /// The title's quiet opening ("Create your ").
    let titlePrefix: String.LocalizationValue
    /// The title's emphasized subject ("first client" / "earnline").
    let titleSubject: String.LocalizationValue

    @Environment(AppModel.self) private var app
    /// Two steps, so two segments. Kept as a constant rather than a parameter:
    /// the copy ("Step 1", "Step 2") is localized per segment, not generated.
    private static let stepCount = 2

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    segment(0)
                    segment(1)
                }
                .frame(height: 2)

                HStack(spacing: 10) {
                    label("Step 1", index: 0)
                    label("Step 2", index: 1)
                }
            }
            .padding(.bottom, 12)

            OnboardingWordmark()

            // Two-tone: the instruction stays quiet, the subject carries the
            // weight. One attributed run rather than two `Text`s, so it wraps
            // as a single paragraph — `Text` + `Text` is deprecated in iOS 26.
            Text(title)
                .appFont(32, .semibold, relativeTo: .largeTitle)
                .tracking(-0.43)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(step + 1) of \(Self.stepCount)"))
    }

    private var title: AttributedString {
        var prefix = AttributedString(localized: titlePrefix)
        prefix.foregroundColor = Theme.label(0.8)
        var subject = AttributedString(localized: titleSubject)
        subject.foregroundColor = Theme.label
        return prefix + subject
    }

    private func segment(_ index: Int) -> some View {
        Capsule()
            .fill(app.accentColor)
            .opacity(index == step ? 1 : 0.2)
            .frame(maxWidth: .infinity)
    }

    private func label(_ title: LocalizedStringKey, index: Int) -> some View {
        Text(title)
            .appFont(12, .medium, relativeTo: .caption)
            .tracking(-0.43)
            .foregroundStyle(app.accentColor)
            .opacity(index == step ? 1 : 0.2)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Wordmark

/// The "earn›line" lockup. A template asset, so it inks with `Theme.label` and
/// survives the dark appearance the Figma does not draw.
struct OnboardingWordmark: View {
    var body: some View {
        Image("Wordmark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 65.42, height: 13.03)
            .foregroundStyle(Theme.label)
            .accessibilityLabel(Text(verbatim: "earn›line"))
    }
}

// MARK: - Panel

/// The bottom sheet-like panel the steps put their controls in: a 50 pt
/// rounded rectangle flush to the bottom edge, lifted off the illustration by
/// a wide upward shadow.
struct OnboardingPanel<Content: View>: View {
    @ViewBuilder var content: Content

    /// The Figma draws a 50 pt radius on all four corners and then runs the
    /// shape past the bottom of the screen, so only the top pair is ever seen.
    private static var cornerRadius: CGFloat { 50 }

    var body: some View {
        VStack(spacing: 36) {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 36)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: Self.cornerRadius,
                topTrailingRadius: Self.cornerRadius
            )
            .fill(Theme.background)
            // Figma: y -47, blur 43.95. SwiftUI's radius is roughly half a
            // Figma blur, hence 22.
            .shadow(color: .black.opacity(0.12), radius: 22, y: -47)
            .ignoresSafeArea(edges: .bottom)
        }
    }

}

// MARK: - Artwork

/// The supplied artwork is intentionally bright. Reduce its luminance in Dark
/// Mode so the white glass surfaces do not flare against the near-black canvas;
/// the source asset and its Figma geometry remain unchanged.
private struct OnboardingArtworkStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .opacity(colorScheme == .dark ? 0.84 : 1)
            .brightness(colorScheme == .dark ? -0.08 : 0)
            .contrast(colorScheme == .dark ? 0.92 : 1)
    }
}

extension View {
    func onboardingArtworkStyle() -> some View {
        modifier(OnboardingArtworkStyle())
    }
}

// MARK: - Field group

/// A titled group inside the panel: the quiet 15 pt header the Figma puts at a
/// 16 pt inset, over a white grouped card.
struct OnboardingFieldGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .appFont(15, .medium, relativeTo: .subheadline)
                .tracking(-0.43)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, 16)
                .padding(.bottom, 2)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
        }
    }
}
