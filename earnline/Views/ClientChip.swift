import SwiftUI

/// A client's colored name pill + rolled-up total, with the Figma "+ Add Income" button.
struct ClientChip: View {
    @Environment(AppModel.self) private var app
    let client: Client
    let total: Decimal
    var onOpen: () -> Void
    var onAdd: () -> Void

    /// Main currency at a fixed size; the secondary currency is appended only when asked.
    private func totalText(showSecondary: Bool) -> Text {
        var primary = AttributedString(app.primaryString(total))
        primary.foregroundColor = Theme.label
        primary.font = .system(size: 16, weight: .medium)
        guard showSecondary else { return Text(primary) }
        var secondary = AttributedString(" · \(app.secondaryString(total))")
        secondary.foregroundColor = Theme.label(0.6)
        secondary.font = .system(size: 14)
        return Text(primary + secondary)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(client.name)
                        .font(.chipName)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(Color(hex: client.colorHex)).interactive(),
                                     in: .capsule)
                        .layoutPriority(1)

                    // Keep the main currency full-size; drop the secondary currency when tight.
                    ViewThatFits(in: .horizontal) {
                        totalText(showSecondary: true).lineLimit(1)
                        totalText(showSecondary: false).lineLimit(1)
                    }
                }
                .padding(.leading, 1)
                .padding(.trailing, 8)
                .padding(.vertical, 1)
                .background(Theme.fillQuaternary, in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.chipStroke, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            // Full "+ Add Income"; collapses to just "+" when there's still not enough room.
            Button(action: onAdd) {
                ViewThatFits(in: .horizontal) {
                    addLabel(showText: true)
                    addLabel(showText: false)
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel("Add Income")
        }
        .padding(.horizontal, 8)
    }

    private func addLabel(showText: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
            if showText {
                Text("Add Income")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.label)
        .contentShape(.rect)
    }
}
