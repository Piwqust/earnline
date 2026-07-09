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
    /// The selected cell's frame, in the scrollable grid's own coordinate
    /// space, reported up via `SelectedCellFrameKey`. Drawing the selection
    /// ring from this — one overlay on top of the *entire* grid, rather than
    /// a per-cell overlay — is what makes it safe to draw bigger than the
    /// cell: a per-cell overlay only "wins" against whichever neighboring
    /// cell happens to paint after it, which is unreliable for accidental
    /// overlap in a plain VStack/HStack grid (that unreliability was the
    /// cropped-square bug). An overlay attached once, above every cell,
    /// is unambiguously the topmost layer no matter which day is selected.
    @State private var selectedCellFrame: CGRect?
    /// The heatmap distribution is the most expensive Insights calculation,
    /// especially for held entries spread across many days. Keep it stable while
    /// the user selects a day or scrubs the chart.
    @State private var cachedDailyEarnings: [Date: Decimal] = [:]

    // Fixed cell metrics — the grid keeps one comfortable size and scrolls
    // horizontally for longer windows rather than shrinking to fit.
    private let cell: CGFloat = 15
    private let cellSpacing: CGFloat = 3
    private let monthGap: CGFloat = 14
    private let weekdayColumnWidth: CGFloat = 16
    private let monthHeaderHeight: CGFloat = 18
    /// Localized single-letter weekday labels, rotated Monday-first to match the
    /// grid (which pins Monday to the top row).
    private let weekdayInitials: [String] = {
        let symbols = Calendar.current.veryShortWeekdaySymbols // Sunday-first
        return Array(symbols.dropFirst()) + [symbols[0]]       // Monday-first
    }()

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

                heatCard(map: map, maxDaily: maxDaily, heatTotal: heatTotal)

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

    // MARK: Heatmap card

    private func heatCard(map: [Date: Decimal], maxDaily: Decimal, heatTotal: Decimal) -> some View {
        ChromeCard {
            VStack(alignment: .leading, spacing: 0) {
                heatGrid(map: map, maxDaily: maxDaily)

                if maxDaily > 0 {
                    legend.padding(.top, 14)
                } else {
                    Text("No earned income in this period")
                        .appFont(11)
                        .foregroundStyle(Theme.label(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }

                if let day = selectedDay {
                    ChromeDivider(inset: 0).padding(.top, 14)
                    dayDetail(day: day, map: map, heatTotal: heatTotal)
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
        }
    }

    // MARK: Heatmap grid — fixed cell size, weekday labels pinned, months scroll

    /// Weekday labels are pinned on the left; the month blocks scroll to their
    /// right so cells keep one comfortable size regardless of how much history
    /// the window covers. Newest month is anchored in view; the soft edge fade
    /// signals that older months lie further along.
    private func heatGrid(map: [Date: Decimal], maxDaily: Decimal) -> some View {
        HStack(alignment: .top, spacing: cellSpacing + 2) {
            weekdayColumn
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: monthGap) {
                    ForEach(months, id: \.self) { month in
                        monthBlock(month, map: map, maxDaily: maxDaily)
                    }
                }
                .padding(.horizontal, 6)
                // Headroom for the selection ring's halo at the very first or
                // last day row, so it sits inside this padded area instead of
                // needing to render past the grid's own measured bounds.
                .padding(.vertical, 4)
                .coordinateSpace(name: "heatGrid")
                .overlay(alignment: .topLeading) {
                    if let frame = selectedCellFrame {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.label, lineWidth: 2)
                            .frame(width: frame.width + 6, height: frame.height + 6)
                            .position(x: frame.midX, y: frame.midY)
                            .allowsHitTesting(false)
                    }
                }
                .onPreferenceChange(SelectedCellFrameKey.self) { selectedCellFrame = $0 }
            }
            .defaultScrollAnchor(.trailing)
            .mask(scrollEdgeFade)
        }
    }

    /// Fades the leading and trailing few points of the scroll so a half-shown
    /// month reads as "there's more", not as a hard-cropped column.
    private var scrollEdgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.97),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    private var weekdayColumn: some View {
        VStack(alignment: .center, spacing: cellSpacing) {
            Color.clear.frame(width: weekdayColumnWidth, height: monthHeaderHeight)
            ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                Text(initial)
                    .appFont(9, .medium)
                    .foregroundStyle(Theme.label(0.4))
                    .frame(width: weekdayColumnWidth, height: cell)
            }
        }
    }

    @ViewBuilder
    private func monthBlock(_ month: Date, map: [Date: Decimal], maxDaily: Decimal) -> some View {
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        // Leading blanks so day 1 sits under its weekday row. The grid pins
        // Monday to the top row, so map weekday (1 = Sunday) onto a Monday-first
        // index: Mon → 0 … Sun → 6.
        let leading = (calendar.component(.weekday, from: month) + 5) % 7
        let weekCount = Int(ceil(Double(leading + daysInMonth) / 7.0))

        VStack(alignment: .leading, spacing: cellSpacing) {
            Text(month.formatted(.dateTime.month(.abbreviated)))
                .appFont(12, .semibold)
                .foregroundStyle(Theme.label(0.55))
                .fixedSize()
                .frame(height: monthHeaderHeight, alignment: .leading)

            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(0..<weekCount, id: \.self) { week in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { row in
                            let dayNumber = week * 7 + row - leading + 1
                            if dayNumber >= 1 && dayNumber <= daysInMonth,
                               let day = calendar.date(byAdding: .day, value: dayNumber - 1, to: month) {
                                dayCell(day, map: map, maxDaily: maxDaily)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date, map: [Date: Decimal], maxDaily: Decimal) -> some View {
        let value = map[calendar.startOfDay(for: day)] ?? 0
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(cellColor(value, maxDaily: maxDaily))
            .frame(width: cell, height: cell)
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(app.accentColor.opacity(0.9), lineWidth: 1.5)
                }
            }
            // Report this cell's frame, in the grid's shared coordinate
            // space, instead of drawing its own halo ring here — see
            // `selectedCellFrame` for why the ring is drawn once, above the
            // whole grid, rather than per-cell.
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SelectedCellFrameKey.self,
                        value: isSelected ? geo.frame(in: .named("heatGrid")) : nil)
                }
            }
            .contentShape(.rect)
            .onTapGesture { select(day) }
            .accessibilityLabel(DateFormat.weekdayAndDate(day))
            .accessibilityValue(value > 0 ? app.primaryString(value) : String(localized: "No income"))
    }

    /// Carries the selected day cell's frame up to `heatGrid`, which draws
    /// the halo ring once, above every cell, instead of each cell drawing its
    /// own ring that could be painted over by a neighbor.
    private struct SelectedCellFrameKey: PreferenceKey {
        static let defaultValue: CGRect? = nil
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    /// Empty days read as a faint neutral fill; earning days glow in the accent,
    /// their opacity scaled by the day's share of the busiest day in the window.
    /// A gentle gamma keeps modest days visible rather than washed out.
    private func cellColor(_ value: Decimal, maxDaily: Decimal) -> Color {
        guard value > 0, maxDaily > 0 else { return Theme.label(0.06) }
        let ratio = NSDecimalNumber(decimal: value).doubleValue
            / NSDecimalNumber(decimal: maxDaily).doubleValue
        let eased = pow(min(max(ratio, 0), 1), 0.55)
        return app.accentColor.opacity(0.20 + 0.80 * eased)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less")
                .appFont(10)
                .foregroundStyle(Theme.label(0.4))
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { step in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(step == 0 ? Theme.label(0.06) : app.accentColor.opacity(0.20 + 0.80 * step))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .appFont(10)
                .foregroundStyle(Theme.label(0.4))
        }
    }

    private func select(_ day: Date?) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.24)) {
            if let day, selectedDay.map({ calendar.isDate($0, inSameDayAs: day) }) == true {
                selectedDay = nil
            } else {
                selectedDay = day
            }
        }
    }

    // MARK: Tapped-day breakdown

    /// A quiet, flat dismiss glyph — the system `xmark.circle.fill` at the
    /// same muted weight `LedgerView`'s search-clear button uses — rather than
    /// a full glass-material circle. Inline within a plain white card, a
    /// glass button's blue tint and shadow reads as a floating action button
    /// competing with the headline amount; a bare monochrome glyph recedes
    /// into a secondary, "tap to dismiss" affordance instead.
    private var clearSelectionButton: some View {
        Button { select(nil) } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.label(0.28))
                // 44 pt hit region around the 22 pt glyph.
                .padding(11)
                .contentShape(.circle)
                .padding(-11)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear selection"))
    }

    /// A tappable date label mirroring `MoneyAmountText`'s tap-to-reveal
    /// idiom: recedes into the app's compact `DD.MM.YY` form by default so
    /// the amount below it stays the focal point, then flips to the fuller
    /// weekday-prefixed form on tap.
    private struct DayHeadlineDate: View {
        let day: Date
        @State private var showFull = false

        private var text: String {
            showFull ? DateFormat.weekdayAndDate(day) : DateFormat.dotted(day)
        }

        var body: some View {
            Button {
                withAnimation(.snappy(duration: 0.24)) { showFull.toggle() }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Text(text)
                    .appFont(11, .semibold)
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .contentTransition(.opacity)
                    .foregroundStyle(Theme.label(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(DateFormat.weekdayAndDate(day)))
        }
    }

    @ViewBuilder
    private func dayDetail(day: Date, map: [Date: Decimal], heatTotal: Decimal) -> some View {
        let dayTotal = map[calendar.startOfDay(for: day)] ?? 0
        let rows = app.dayContributions(on: day, clients: clients)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    DayHeadlineDate(day: day)
                        .id(day)
                    MoneyAmountText(baseAmount: dayTotal, size: 26, weight: .bold, design: .rounded,
                                     relativeTo: .title, color: Theme.label)
                }
                Spacer(minLength: 8)
                clearSelectionButton
            }
            .accessibilityElement(children: .combine)

            if heatTotal > 0 {
                // A nested stat chip — the Revolut "Budget"/"Scheduled
                // payments" idiom — instead of a label-and-bar floating
                // directly on the card's white background. Boxing it gives
                // this one summary figure a visible edge separating it from
                // the headline amount above and the line items below, rather
                // than all three just running together in one flat list.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Share of period")
                            .appFont(12)
                            .foregroundStyle(Theme.label(0.45))
                        Spacer()
                        Text(percentString(ratio(dayTotal, heatTotal)))
                            .appFont(13, .semibold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(app.accentColor)
                    }
                    shareBar(ratio(dayTotal, heatTotal), color: app.accentColor)
                }
                .padding(10)
                .background(Theme.label(0.04), in: .rect(cornerRadius: 14, style: .continuous))
            }

            if rows.isEmpty {
                Text("No income recorded on this day")
                    .appFont(13)
                    .foregroundStyle(Theme.label(0.4))
                    .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        // Per-row share of the day (the Revolut breakdown idiom)
                        // only when there's more than one line to compare.
                        contributionRow(row, dayTotal: dayTotal, showShare: rows.count > 1)
                        if index < rows.count - 1 {
                            ChromeDivider(inset: 20)
                        }
                    }
                }
            }
        }
    }

    private func contributionRow(_ row: (entry: Entry, amount: Decimal, isHeldSlice: Bool),
                                 dayTotal: Decimal, showShare: Bool) -> some View {
        let entry = row.entry
        let dotColor = Color(hex: entry.client?.colorHex ?? Theme.statusPaid.hexString)
        return HStack(alignment: .top, spacing: 11) {
            // Same rounded-square swatch as `clientRow`'s "Top clients" list
            // below — both represent a client's color on this one screen, so
            // a dot here and a square there read as an unintentional mismatch
            // rather than two idioms.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.client?.name ?? String(localized: "No client"))
                        .appFont(15, .semibold)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(app.primaryString(row.amount))
                        .appFont(15, .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(Theme.label)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(lineDescription(entry))
                        .appFont(12)
                        .foregroundStyle(Theme.label(0.5))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if showShare, dayTotal > 0 {
                        Text(percentString(ratio(row.amount, dayTotal)))
                            .appFont(11, .medium, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(Theme.label(0.4))
                    }
                }
                if row.isHeldSlice, let hold = entry.holdUntil {
                    let full = app.toBase(entry.amount, code: entry.currencyCode)
                    Text("Slice of \(app.primaryString(full)) · held until \(DateFormat.dotted(hold))")
                        .appFont(11)
                        .foregroundStyle(Theme.label(0.4))
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func lineDescription(_ entry: Entry) -> String {
        if let project = entry.project, !project.isEmpty {
            return "\(project) : \(entry.task)"
        }
        return entry.task
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

    /// Horizontal share bar, scaled against the reference passed in.
    ///
    /// The track and fill are two plain rectangles clipped together to one
    /// capsule, not a smaller capsule floating inside a bigger one. Two
    /// independently-rounded capsules leave a visible gap past the fill's
    /// rounded corners, so a small share (a single day against a whole
    /// quarter, easily 1–2%) reads as a stray dot sitting a few points into
    /// an otherwise empty track instead of a sliver flush with its edge.
    private func shareBar(_ share: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.label(0.08))
                Rectangle()
                    .fill(color.gradient)
                    .frame(width: max(3, geo.size.width * min(max(share, 0), 1)))
            }
        }
        .frame(height: 6)
        .clipShape(.capsule)
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

    /// Compact bar label, e.g. "+1.5k" / "−11k" — like `signedCompact` but with
    /// an explicit plus so a rise reads unambiguously against a dip on the bar.
    private func signedCompactLabel(_ value: Double) -> String {
        value > 0 ? "+\(signedCompact(value))" : signedCompact(value)
    }

    /// Compact axis label, e.g. "1.2k", carrying a leading minus for negatives
    /// so the month-over-month axis reads correctly below zero.
    private func signedCompact(_ value: Double) -> String {
        let sign = value < 0 ? "−" : ""
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return "\(sign)\((magnitude / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M"
        }
        if magnitude >= 1000 {
            return "\(sign)\((magnitude / 1000).formatted(.number.precision(.fractionLength(0...1))))k"
        }
        return "\(sign)\(magnitude.formatted(.number.precision(.fractionLength(0))))"
    }
}
