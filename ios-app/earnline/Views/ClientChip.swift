import SwiftUI

/// A client's colored name pill + rolled-up total, with the "+ Line" button.
/// Tapping the name opens the client; tapping the total flips the shown
/// currency. While this client's composer is open the button reads "Close",
/// since the same tap collapses it.
struct ClientChip: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let client: Client
    let total: Decimal
    var isComposing: Bool = false
    /// Hidden in ledger search mode — adding a line there would fight the filter.
    var showsAdd: Bool = true
    var onOpen: () -> Void
    var onAdd: () -> Void

    var body: some View {
        // Same guard as `EntryRow`: a sync pull can delete this client while
        // the chip is on screen, and one more render before the row leaves
        // the List would trap reading the invalidated model.
        if client.isInvalidated {
            EmptyView()
        } else {
            chipBody
        }
    }

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
    }

    private var chipBody: some View {
        layout {
            layout {
                Button(action: onOpen) {
                    Text(client.name)
                        .appFont(16, .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(Color(hex: client.colorHex)).interactive(),
                                     in: .capsule)
                        // The drawn capsule is ~19 pt tall; this reaches into the
                        // row's own padding so the target approaches 44 pt
                        // without thickening the ledger's densest row.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                MoneyAmountText(baseAmount: total,
                                size: 16, weight: .medium,
                                color: Theme.label,
                                minimumScaleFactor: 0.7)
                    // Keep the rolled-up total readable; a long name truncates
                    // before the amount does.
                    .layoutPriority(1)
                    .animation(.snappy(duration: 0.3), value: total)
            }
            .padding(.leading, 1)
            .padding(.trailing, 8)
            .padding(.vertical, 1)
            .background(Theme.fillQuaternary, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.chipStroke, lineWidth: 0.5))
            // The name + total win the row over the button label, so a long
            // client name shrinks the button instead of getting crushed itself.
            .layoutPriority(1)

            if showsAdd {
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }

                // "+ Line" / "× Close"; collapses to just the "+" icon when the
                // client name is long enough to crowd the row.
                Button(action: onAdd) {
                    ViewThatFits(in: .horizontal) {
                        addLabel(showText: true)
                        addLabel(showText: false)
                    }
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.25), value: isComposing)
                .accessibilityLabel(isComposing ? "Close" : "Add line")
            }
        }
        .padding(.horizontal, 8)
    }

    private func addLabel(showText: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isComposing ? "xmark" : "plus")
                .appFont(16, .medium)
                .contentTransition(.symbolEffect(.replace))
            if showText {
                Text(isComposing ? "Close" : "Line")
                    .appFont(15, .semibold)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .foregroundStyle(Theme.label)
        // Same reasoning as the client capsule: the "+ Line" / "× Close" label is
        // only ~18 pt tall, so grow the touch region into the row's padding
        // rather than the row itself.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
}
