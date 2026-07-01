import SwiftUI

/// The floating glass header: "Earned in <month>" with the running total.
struct SummaryPill: View {
    @Environment(AppModel.self) private var app
    let month: Date
    let total: Decimal

    /// Tracks the prior total so the digits roll in the natural direction.
    @State private var previousTotal: Decimal = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Earned in \(DateFormat.month(month))")
                .font(.labelMed)
                .foregroundStyle(Theme.label(0.6))
                .id(month)
                .transition(.blurReplace)
            Spacer(minLength: 12)
            MoneyAmountText(baseAmount: total,
                            font: .summaryTotal,
                            color: Theme.label,
                            countsDownFrom: previousTotal)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.summary))
        .contentShape(.rect(cornerRadius: Theme.Radius.summary))
        .animation(.snappy(duration: 0.34), value: total)
        .animation(.snappy(duration: 0.34), value: month)
        .onChange(of: total) { oldValue, _ in previousTotal = oldValue }
    }
}
