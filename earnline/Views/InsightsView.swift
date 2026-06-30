import SwiftUI
import SwiftData
import Charts

/// A lightweight analytics screen over earned income: a 12-month bar chart plus
/// summary stat cards and a top-clients list. All figures are in the base
/// currency and exclude canceled lines (see `AppModel` earned-total semantics).
struct InsightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    private var series: [(month: Date, total: Decimal)] { app.monthlySeries(clients) }
    private var topClients: [(client: Client, total: Decimal)] { app.topClients(clients) }

    private var ytdTotal: Decimal {
        let year = Calendar.current.component(.year, from: .now)
        return series
            .filter { Calendar.current.component(.year, from: $0.month) == year }
            .reduce(Decimal.zero) { $0 + $1.total }
    }
    private var windowTotal: Decimal { series.reduce(Decimal.zero) { $0 + $1.total } }
    private var averageMonth: Decimal {
        series.isEmpty ? 0 : windowTotal / Decimal(series.count)
    }
    private var bestMonth: (month: Date, total: Decimal)? {
        series.max { $0.total < $1.total }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    chartCard
                    statGrid
                    if !topClients.isEmpty { topClientsCard }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 12 months")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label(0.5))
            Chart(series, id: \.month) { point in
                BarMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("Earned", doubleValue(point.total))
                )
                .foregroundStyle(Theme.blue.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { value in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compact(amount))
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: Stat cards

    private var statGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCard("This year", app.primaryString(ytdTotal))
            statCard("Avg / month", app.primaryString(averageMonth.rounded()))
            statCard("Best month", bestMonth.map { app.primaryString($0.total) } ?? "—",
                     caption: bestMonth.map { DateFormat.month($0.month) })
            statCard("12-mo total", app.primaryString(windowTotal))
        }
    }

    private func statCard(_ title: String, _ value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.label(0.5))
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label(0.4))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: Top clients

    private var topClientsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top clients")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label(0.5))
            ForEach(Array(topClients.enumerated()), id: \.element.client) { _, row in
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: row.client.colorHex)).frame(width: 10, height: 10)
                    Text(row.client.name).foregroundStyle(Theme.label)
                    Spacer(minLength: 8)
                    Text(app.primaryString(row.total))
                        .monospacedDigit()
                        .foregroundStyle(Theme.label(0.7))
                }
                .font(.system(size: 15))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: Helpers

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// Compact axis label, e.g. "1.2k".
    private func compact(_ value: Double) -> String {
        if value >= 1000 {
            return "\((value / 1000).formatted(.number.precision(.fractionLength(0...1))))k"
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
