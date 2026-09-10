import SwiftUI

/// A month separator in the continuous ledger, carrying that month's subtotal.
struct MonthDivider: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var total: Decimal? = nil

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 10))
    }

    var body: some View {
        layout {
            if !typeSize.isAccessibilitySize { Rectangle().fill(Theme.hairline).frame(width: 28, height: 1) }
            Text(title)
                .appFont(14, .medium)
                .foregroundStyle(.secondary)
            if !typeSize.isAccessibilitySize { Rectangle().fill(Theme.hairline).frame(height: 1) }
            if let total {
                MoneyAmountText(baseAmount: total,
                                size: 13, weight: .medium,
                                color: Theme.label(0.4),
                                minimumScaleFactor: 0.7)
                    .animation(.snappy(duration: 0.3), value: total)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
