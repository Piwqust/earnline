import SwiftUI

/// A client's colored name pill + rolled-up total, with the "+ Line" button.
/// Tapping the name opens the client; tapping the total flips the shown currency.
struct ClientChip: View {
    let client: Client
    let total: Decimal
    var onOpen: () -> Void
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Button(action: onOpen) {
                    Text(client.name)
                        .font(.chipName)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(Color(hex: client.colorHex)).interactive(),
                                     in: .capsule)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)

                MoneyAmountText(baseAmount: total,
                                font: .chipTotal,
                                color: Theme.label,
                                minimumScaleFactor: 0.7)
                    .animation(.snappy(duration: 0.3), value: total)
            }
            .padding(.leading, 1)
            .padding(.trailing, 8)
            .padding(.vertical, 1)
            .background(Theme.fillQuaternary, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.chipStroke, lineWidth: 0.5))

            Spacer(minLength: 8)

            // "+ Line"; collapses to just "+" when there's still not enough room.
            Button(action: onAdd) {
                ViewThatFits(in: .horizontal) {
                    addLabel(showText: true)
                    addLabel(showText: false)
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel("Add line")
        }
        .padding(.horizontal, 8)
    }

    private func addLabel(showText: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
            if showText {
                Text("Line")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.label)
        .contentShape(.rect)
    }
}
