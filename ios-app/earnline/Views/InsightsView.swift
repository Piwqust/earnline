import SwiftUI
import SwiftData
import Charts

/// Income at a glance, in the ChatGPT card dialect: a centered-title sheet on
/// the gray background with grouped white cards. A daily-earnings heatmap sits
/// up top (tap a cell to expand that day), a cumulative earnings trend chart
/// below it, then the headline stats and top clients. All figures are in the
/// base currency; earned totals exclude canceled lines. Held lines spread their
/// amount evenly from their date through the hold-release day.
struct InsightsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Client.sortIndex) private var clients: [Client]

    /// Charted window in months, behind the Health-style Week/Month/Year toggle.
    @State private var windowMonths = 3
    /// The tapped day, whose cell is ringed and whose breakdown expands below.
    @State private var selectedDay: Date?
    /// Scrub position on the trend chart; snapped to the nearest plotted day.
    @State private var chartSelection: Date?
    /// The heatmap distribution is the most expensive Insights calculation,
    /// especially for held entries spread across many days. Keep it stable while
    /// the user selects a day or scrubs the chart.
    @State private var cachedDailyEarnings: [Date: Decimal] = [:]

    private var calendar: Calendar { .current }

    private var dailyEarningsCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(windowMonths)
        for client in clients {
            hasher.combine(client.id)
            for entry in client.entries {
                hasher.combine(entry.id)
                hasher.combine(entry.amount)
                hasher.combine(entry.currencyCode)
                hasher.combine(entry.date)
                hasher.combine(entry.holdUntil)
                hasher.combine(entry.statusRaw)
            }
        }
        return hasher.finalize()
    }

    private var unsupportedCurrencyCount: Int {
        clients.reduce(into: 0) { count, client in
            count += client.entries.count { !app.canConvert($0.currencyCode) }
        }
    }

    private var trendChartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 280 : 210
    }

    // MARK: Window (whole calendar months, oldest first)

    private var months: [Date] {
        let thisMonth = DateFormat.monthStart(of: .now)
        return (0..<max(windowMonths, 1)).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: thisMonth)
        }
    }
    private var windowStart: Date { months.first ?? DateFormat.monthStart(of: .now) }
    private var windowEnd: Date {
        let thisMonth = DateFormat.monthStart(of: .now)
        guard let next = calendar.date(byAdding: .month, value: 1, to: thisMonth),
              let last = calendar.date(byAdding: .day, value: -1, to: next) else { return thisMonth }
        return last
    }

    // MARK: Series-backed figures for the stats card

    private var series: [(month: Date, total: Decimal)] {
        app.monthlySeries(clients, lastNMonths: windowMonths)
    }
    private var windowTotal: Decimal { series.reduce(Decimal.zero) { $0 + $1.total } }
    private var activeMonthCount: Int { series.count { $0.total > 0 } }
    private var averageMonth: Decimal {
        activeMonthCount == 0 ? 0 : windowTotal / Decimal(activeMonthCount)
    }
    private var bestMonth: (month: Date, total: Decimal)? {
        guard windowTotal > 0 else { return nil }
        return series.max { $0.total < $1.total }
    }

    /// Year-to-date, independent of the charted window.
    private var ytdTotal: Decimal {
        let year = calendar.component(.year, from: .now)
        var sum = Decimal.zero
        for client in clients {
            for entry in client.entries
            where entry.status.isIncludedInEarnedTotals
                && calendar.component(.year, from: entry.date) == year {
                sum += app.toBase(entry.amount, code: entry.currencyCode)
            }
        }
        return sum
    }

    var body: some View {
        let map = cachedDailyEarnings
        let maxDaily = map.values.max() ?? 0
        let heatTotal = map.values.reduce(Decimal.zero, +)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                periodPicker

                if unsupportedCurrencyCount > 0 {
                    Label("\(unsupportedCurrencyCount) line(s) are excluded from these totals because no conversion rate is set.",
                          systemImage: "exclamationmark.triangle.fill")
                        .appFont(13)
                        .foregroundStyle(Theme.statusProgress)
                        .accessibilityLabel("\(unsupportedCurrencyCount) lines are excluded from consolidated totals because no conversion rate is set")
                }

                EarningsHeatmapCard(clients: clients,
                                    map: map,
                                    maxDaily: maxDaily,
                                    heatTotal: heatTotal,
                                    months: months,
                                    selectedDay: $selectedDay)

                VStack(alignment: .leading, spacing: 0) {
                    CardHeader("Month over month")
                    trendCard
                }

                statsCard

                let breakdown = app.clientTotals(clients, lastNMonths: windowMonths)
                if !breakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        CardHeader("Top clients")
                        topClientsCard(breakdown)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Shared sheet header — leading glass ✕, centered title, soft scroll-edge
        // frost. See `sheetHeader`.
        .sheetHeader("Insights", onClose: { dismiss() })
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .task(id: dailyEarningsCacheKey) {
            cachedDailyEarnings = app.dailyEarnings(clients, from: windowStart, through: windowEnd)
        }
    }

    // MARK: Period

    private var periodPicker: some View {
        // Labels match the actual windows (3/6/12 months) — the Health-style
        // "Week/Month/Year" wording lied about what was charted.
        Picker("", selection: $windowMonths) {
            Text("3M").tag(3)
            Text("6M").tag(6)
            Text("Y").tag(12)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Time range")
        .onChange(of: windowMonths) {
            selectedDay = nil
            chartSelection = nil
        }
    }

    // MARK: Trend chart — month-over-month change in earned revenue

    private var deltas: [(month: Date, delta: Decimal, total: Decimal)] {
        app.monthlyDeltas(clients, lastNMonths: windowMonths)
    }

    private func selectedDelta(_ data: [(month: Date, delta: Decimal, total: Decimal)])
        -> (month: Date, delta: Decimal, total: Decimal)? {
        guard let chartSelection else { return nil }
        return data.first { calendar.isDate($0.month, equalTo: chartSelection, toGranularity: .month) }
    }

    /// Each bar is a month's earned revenue minus the previous month's — green
    /// when it grew, red when it dipped. Every bar carries its own compact
    /// value label (e.g. "+1.5k", "−11k") pinned at the bar's outer end, so a
    /// single outsized swing — a big month followed by a quiet one — can't
    /// squash the smaller months into unreadable slivers on the shared scale.
    /// Scrub a bar for the exact figure and month.
    private var trendCard: some View {
        let data = deltas
        let selected = selectedDelta(data)
        let hasData = data.contains { $0.delta != 0 || $0.total != 0 }
        // Only label bars directly on the Week/Month windows; a 12-bar Year
        // would crowd, so there the scrub callout carries the exact value.
        let labelBars = data.count <= 7
        return ChromeCard {
            Chart {
                ForEach(data, id: \.month) { point in
                    let isSelected = selected.map {
                        calendar.isDate($0.month, equalTo: point.month, toGranularity: .month)
                    } ?? false
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Change", doubleValue(point.delta)),
                        width: .ratio(0.62)
                    )
                    .foregroundStyle(barStyle(point, selected: selected))
                    .cornerRadius(5)
                    // The label rides the outer end of the bar (above a rise,
                    // below a dip) and is suppressed for the scrubbed bar, whose
                    // bigger callout takes over.
                    .annotation(position: point.delta >= 0 ? .top : .bottom,
                                spacing: 4,
                                overflowResolution: .init(x: .disabled, y: .fit(to: .chart))) {
                        if labelBars, point.delta != 0, !isSelected {
                            Text(signedCompactLabel(doubleValue(point.delta)))
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(point.delta >= 0 ? Theme.green : Theme.statusCanceled)
                        }
                    }
                }

                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Theme.label(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let selected {
                    RuleMark(x: .value("Month", selected.month, unit: .month))
                        .foregroundStyle(Theme.label(0.14))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            deltaCallout(selected)
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(signedCompact(amount))
                                .font(.caption2)
                                .foregroundStyle(Theme.label(0.4))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: max(windowMonths / 6, 1))) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.label(0.5))
                }
            }
            .chartXSelection(value: $chartSelection)
            .frame(height: trendChartHeight)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .overlay {
                if !hasData {
                    Text("No earned income in this period")
                        .appFont(11)
                        .foregroundStyle(Theme.label(0.4))
                }
            }
        }
    }

    private func barStyle(_ point: (month: Date, delta: Decimal, total: Decimal),
                          selected: (month: Date, delta: Decimal, total: Decimal)?) -> AnyShapeStyle {
        let base = point.delta >= 0 ? Theme.green : Theme.statusCanceled
        if let selected, !calendar.isDate(selected.month, equalTo: point.month, toGranularity: .month) {
            return AnyShapeStyle(base.opacity(0.3))
        }
        return AnyShapeStyle(base.gradient)
    }

    private func deltaCallout(_ point: (month: Date, delta: Decimal, total: Decimal)) -> some View {
        let up = point.delta >= 0
        return VStack(spacing: 1) {
            Text("\(up ? "+" : "−")\(app.primaryString(up ? point.delta : -point.delta))")
                .appFont(12, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(up ? Theme.green : Theme.statusCanceled)
            Text(DateFormat.monthAndYear(point.month))
                .appFont(9)
                .foregroundStyle(Theme.label(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface, in: .rect(cornerRadius: 8))
        .shadow(color: Theme.label(0.12), radius: 6, y: 2)
    }

    // MARK: Stats — three headline figures in one card

    private var statsCard: some View {
        ChromeCard {
            HStack(alignment: .top, spacing: 8) {
                heroStat("This year", value: app.primaryString(ytdTotal.rounded()))
                heroStat("Best month", value: bestMonth.map { app.primaryString($0.total.rounded()) } ?? "—")
                heroStat("Avg / month", value: app.primaryString(averageMonth.rounded()))
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
        }
    }

    private func heroStat(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .appFont(13)
                .foregroundStyle(Theme.label(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .appFont(23, .bold, design: .rounded, relativeTo: .title2)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Top clients — a ranked list beside a glowing share orb

    /// A compact ranked list carries the accessible breakdown (name, percent,
    /// amount); a glowing `ClientOrbChart` sits in the card's upper-right
    /// corner, colors matching the row dots. Top-aligning the row lets the
    /// orb read as a corner ornament rather than something wedged into the
    /// middle of a taller list.
    private func topClientsCard(_ breakdown: [(client: Client, total: Decimal)]) -> some View {
        let total = breakdown.reduce(Decimal.zero) { $0 + $1.total }
        let shown = Array(breakdown.prefix(4))
        let othersTotal = breakdown.dropFirst(4).reduce(Decimal.zero) { $0 + $1.total }
        let segments = shown.map { (color: Color(hex: $0.client.colorHex), value: $0.total, isMuted: false) }
            + (othersTotal > 0 ? [(color: Theme.label(0.3), value: othersTotal, isMuted: true)] : [])

        return ChromeCard {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.client) { index, row in
                        compactClientRow(name: row.client.name, total: row.total,
                                         color: Color(hex: row.client.colorHex), whole: total)
                        if index < shown.count - 1 || othersTotal > 0 {
                            ChromeDivider(inset: 0)
                        }
                    }
                    if othersTotal > 0 {
                        compactClientRow(name: String(localized: "Other clients"), total: othersTotal,
                                         color: Theme.label(0.3), whole: total)
                    }
                }
                ClientOrbChart(segments: segments)
            }
            .padding(16)
        }
    }

    /// One list row: color dot, name with its percent underneath, amount
    /// trailing. No share bar here — the orb beside the list carries that.
    private func compactClientRow(name: String, total: Decimal, color: Color, whole: Decimal) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .appFont(14, .semibold)
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                Text(percentString(ratio(total, whole)))
                    .appFont(11, .medium, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.label(0.45))
            }
            Spacer(minLength: 6)
            Text(app.primaryString(total))
                .appFont(14, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Helpers

    private func ratio(_ value: Decimal, _ whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return NSDecimalNumber(decimal: value).doubleValue / NSDecimalNumber(decimal: whole).doubleValue
    }

    /// "37%" — clamped so a wild outlier can't blow the layout apart.
    private func percentString(_ fraction: Double) -> String {
        "\(Int((min(fraction, 9.99) * 100).rounded()))%"
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// Compact bar label, e.g. "+2k" / "−11k" — like `signedCompact` but with
    /// an explicit plus so a rise reads unambiguously against a dip on the bar.
    private func signedCompactLabel(_ value: Double) -> String {
        value > 0 ? "+\(signedCompact(value))" : signedCompact(value)
    }

    /// Compact axis label, e.g. "1k", carrying a leading minus for negatives
    /// so the month-over-month axis reads correctly below zero.
    private func signedCompact(_ value: Double) -> String {
        let sign = value < 0 ? "−" : ""
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return "\(sign)\(CurrencyFormatter.grouped(Decimal(magnitude / 1_000_000), code: app.baseCurrencyCode))M"
        }
        if magnitude >= 1000 {
            return "\(sign)\(CurrencyFormatter.grouped(Decimal(magnitude / 1000), code: app.baseCurrencyCode))k"
        }
        return "\(sign)\(CurrencyFormatter.grouped(Decimal(magnitude), code: app.baseCurrencyCode))"
    }
}
