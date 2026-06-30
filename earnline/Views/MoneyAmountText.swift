import SwiftUI

/// A tappable money label. It prefers the app's primary currency (USD by default)
/// and flips to the secondary currency for quick comparison.
struct MoneyAmountText: View {
    @Environment(AppModel.self) private var app

    let baseAmount: Decimal
    var font: Font
    var color: Color = Theme.label
    var lineLimit: Int? = 1
    var minimumScaleFactor: CGFloat = 0.78
    var countsDownFrom: Decimal?
    /// When the source amount's currency has no rate, the base value is a 1:1
    /// fallback — append a subtle "·?" so it isn't mistaken for an exact total.
    var isApproximate: Bool = false

    @State private var showSecondary = false

    private var displayedAmount: Decimal {
        showSecondary ? app.secondary(baseAmount) : baseAmount
    }

    private var displayedCode: String {
        showSecondary ? app.secondaryCurrencyCode : app.baseCurrencyCode
    }

    private var nextCode: String {
        showSecondary ? app.baseCurrencyCode : app.secondaryCurrencyCode
    }

    private var amountText: String {
        CurrencyFormatter.string(displayedAmount, code: displayedCode)
    }

    private var countsDown: Bool {
        guard let countsDownFrom else { return false }
        return baseAmount < countsDownFrom
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                showSecondary.toggle()
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 2) {
                Text(amountText)
                    .contentTransition(.numericText(countsDown: countsDown))
                if isApproximate {
                    Text("·?")
                        .foregroundStyle(color.opacity(0.4))
                }
            }
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isApproximate ? "\(amountText), approximate" : amountText)
        .accessibilityHint(Text("Tap to show \(nextCode)"))
    }
}
