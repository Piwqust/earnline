import SwiftUI

/// Step 1 — "Create your **first client**".
///
/// The panel is a live preview of the thing being made: the chip at the top is
/// the same colored capsule the ledger will show, updating as the owner types
/// and picks. The color card is the app's own `ClientColorGrid`, not a copy.
struct OnboardingClientStep: View {
    @Binding var name: String
    @Binding var colorHex: String
    /// Shown under the field once there is something to complain about. The
    /// flow owns validation, since it also owns the CTA's enabled state.
    let validationMessage: String?
    let submit: () -> Void

    /// The chip reads as the client the moment there is anything to read.
    private var previewName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Client name") : trimmed
    }

    var body: some View {
        VStack(spacing: 12) {
            identityChip
            nameField
            colorField
            if let validationMessage {
                Text(validationMessage)
                    .appFont(13, relativeTo: .footnote)
                    .foregroundStyle(Theme.statusCanceled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
            }
        }
        .accessibilityIdentifier("onboarding.step.client")
    }

    // MARK: Live chip

    private var identityChip: some View {
        Text(previewName)
            .appFont(24, .semibold, relativeTo: .title2)
            .tracking(-0.24)
            .foregroundStyle(.white.opacity(0.96))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(Color(hex: colorHex)).interactive(), in: .capsule)
            .padding(.vertical, 12)
            .animation(.snappy, value: colorHex)
            .accessibilityHidden(true)
    }

    // MARK: Fields

    private var nameField: some View {
        OnboardingFieldGroup(title: "Name") {
            TextField("Client name", text: $name)
                .appFont(17, relativeTo: .body)
                .tracking(-0.43)
                .foregroundStyle(Theme.label)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submit)
                .onChange(of: name) { _, newValue in
                    name = Validation.capped(newValue, max: Limits.maxClientNameLength)
                }
                .frame(minHeight: 52)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("onboarding.clientName")
        }
    }

    private var colorField: some View {
        OnboardingFieldGroup(title: "Color") {
            // The shared grid already carries the Figma's 30 pt dots, 16 pt
            // padding, and selection ring — it is the same control the New- and
            // Edit-client sheets use.
            ClientColorGrid(selection: $colorHex)
        }
    }
}
