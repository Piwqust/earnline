import SwiftUI

/// A client's colored name pill + rolled-up total, with a glass "+" to add a line.
struct ClientChip: View {
    @Environment(AppModel.self) private var app
    let client: Client
    let total: Decimal
    var onOpen: () -> Void
    var onAdd: () -> Void

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

                    HStack(spacing: 4) {
                        Text(app.primaryString(total))
                            .font(.chipTotal)
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                        Text("· \(app.secondaryString(total))")
                            .font(.caption)
                            .foregroundStyle(Theme.label(0.6))
                            .lineLimit(1)
                    }
                    .layoutPriority(-1)
                }
                .padding(.leading, 1)
                .padding(.trailing, 8)
                .padding(.vertical, 1)
                .background(Theme.fillQuaternary, in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.chipStroke, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            GlassCircleButton(action: onAdd)
        }
        .padding(.horizontal, 8)
    }
}
