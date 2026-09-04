import SwiftUI
import SwiftData

/// The daily-earnings heatmap card from Insights, split into its own view: a
/// fixed-cell month grid (weekday labels pinned, months scroll), a legend, and
/// the tapped-day breakdown that expands below. It owns only its selection-ring
/// frame; the selected day is bound back to `InsightsView` so switching the
/// charted window can clear it. Figures are base-currency, precomputed by the
/// parent and passed in as `map`.
struct EarningsHeatmapCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let map: [Date: Decimal]
    let maxDaily: Decimal
    let heatTotal: Decimal
    let months: [Date]
    @Binding var selectedDay: Date?

    @State private var hasRevealedData = false
    @State private var selectedRows: [(entry: Entry, amount: Decimal, isHeldSlice: Bool)] = []
    @State private var dayLoadError: String?

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

    // MARK: Heatmap card

    var body: some View {
        ChromeCard {
            VStack(alignment: .leading, spacing: 0) {
                heatGrid(map: map, maxDaily: maxDaily)

                if maxDaily > 0 {
                    legend.padding(.top, 14)
                } else {
                    Text("No earned income in this period")
                        .appFont(11)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }

                if let day = selectedDay {
                    ChromeDivider(inset: 0).padding(.top, 14)
                    dayDetail(day: day, map: map, heatTotal: heatTotal)
                        .padding(.top, 14)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                        .accessibilityIdentifier("insights.selectedDay")
                }
            }
            .padding(16)
        }
        .opacity(hasRevealedData ? 1 : 0.45)
        .scaleEffect(hasRevealedData ? 1 : 0.985, anchor: .top)
        .task {
            guard !hasRevealedData else { return }
            await Task.yield()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
                hasRevealedData = true
            }
        }
        .task(id: selectedDay) {
            loadDayDetails(for: selectedDay)
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
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
                .padding(.vertical, 4)
                .overlayPreferenceValue(DayCellBoundsKey.self) { anchors in
                    GeometryReader { proxy in
                        let frames = anchors.mapValues { proxy[$0] }
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(.rect)
                                .simultaneousGesture(
                                    SpatialTapGesture().onEnded { event in
                                        selectNearest(to: event.location, frames: frames)
                                    }
                                )

                            if let selectedDay,
                               let frame = frames[calendar.startOfDay(for: selectedDay)] {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(app.accentColor, lineWidth: 2)
                                    .frame(width: frame.width + 6, height: frame.height + 6)
                                    .position(x: frame.midX, y: frame.midY)
                                    .shadow(color: app.accentColor.opacity(0.28), radius: 4)
                                    .allowsHitTesting(false)
                                    .animation(
                                        reduceMotion ? nil : .snappy(duration: 0.25, extraBounce: 0.08),
                                        value: selectedDay
                                    )
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            .mask(scrollEdgeFade)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Income calendar")
        .accessibilityValue(heatmapAccessibilityValue)
        .accessibilityHint("Swipe up or down to move between days")
        .accessibilityAdjustableAction { direction in moveSelection(direction) }
        .accessibilityIdentifier("insights.heatmap")
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
                    .foregroundStyle(.tertiary)
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
                .foregroundStyle(.secondary)
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
        let isToday = calendar.isDateInToday(day)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(cellColor(value, maxDaily: maxDaily))
            .frame(width: cell, height: cell)
            .overlay {
                if isToday && selectedDay.map({ !calendar.isDate($0, inSameDayAs: day) }) != false {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(app.accentColor.opacity(0.78), lineWidth: 1.25)
                }
            }
            .anchorPreference(key: DayCellBoundsKey.self, value: .bounds) { anchor in
                [calendar.startOfDay(for: day): anchor]
            }
            .accessibilityHidden(true)
    }

    private struct DayCellBoundsKey: PreferenceKey {
        static let defaultValue: [Date: Anchor<CGRect>] = [:]
        static func reduce(value: inout [Date: Anchor<CGRect>], nextValue: () -> [Date: Anchor<CGRect>]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
                .foregroundStyle(.tertiary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { step in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(step == 0 ? Theme.label(0.06) : app.accentColor.opacity(0.20 + 0.80 * step))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .appFont(10)
                .foregroundStyle(.tertiary)
        }
    }

    private func selectNearest(to location: CGPoint, frames: [Date: CGRect]) {
        guard let nearest = frames.min(by: {
            hypot($0.value.midX - location.x, $0.value.midY - location.y)
                < hypot($1.value.midX - location.x, $1.value.midY - location.y)
        })?.key else { return }
        select(nearest)
    }

    private var availableDays: [Date] {
        months.flatMap { month -> [Date] in
            guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
            return range.compactMap { day in
                calendar.date(byAdding: .day, value: day - 1, to: month).map(calendar.startOfDay(for:))
            }
        }.sorted()
    }

    private var heatmapAccessibilityValue: String {
        guard let selectedDay else { return String(localized: "No day selected") }
        let amount = map[calendar.startOfDay(for: selectedDay)] ?? .zero
        return "\(DateFormat.weekdayAndDate(selectedDay)), \(app.primaryString(amount))"
    }

    private func moveSelection(_ direction: AccessibilityAdjustmentDirection) {
        let days = availableDays
        guard !days.isEmpty else { return }
        let currentIndex = selectedDay.flatMap { selected in
            days.firstIndex { calendar.isDate($0, inSameDayAs: selected) }
        } ?? max(days.count - 1, 0)
        let nextIndex: Int
        switch direction {
        case .increment: nextIndex = min(currentIndex + 1, days.count - 1)
        case .decrement: nextIndex = max(currentIndex - 1, 0)
        @unknown default: return
        }
        setSelectedDay(days[nextIndex])
    }

    private func select(_ day: Date?) {
        let next: Date?
        if let day, selectedDay.map({ calendar.isDate($0, inSameDayAs: day) }) == true {
            next = nil
        } else {
            next = day
        }
        setSelectedDay(next)
    }

    private func setSelectedDay(_ day: Date?) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25, extraBounce: 0.08)) {
            selectedDay = day
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
                .foregroundStyle(.tertiary)
                // 44 pt hit region around the 22 pt glyph.
                .padding(11)
                .contentShape(.circle)
                .padding(-11)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear selection"))
        .accessibilityIdentifier("insights.clearDaySelection")
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
            } label: {
                Text(text)
                    .appFont(11, .semibold)
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .contentTransition(.opacity)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showFull)
            .accessibilityLabel(Text(DateFormat.weekdayAndDate(day)))
        }
    }

    @ViewBuilder
    private func dayDetail(day: Date, map: [Date: Decimal], heatTotal: Decimal) -> some View {
        let dayTotal = map[calendar.startOfDay(for: day)] ?? 0
        let rows = selectedRows
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
                            .foregroundStyle(.tertiary)
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

            if let dayLoadError {
                Label(dayLoadError, systemImage: "exclamationmark.triangle")
                    .appFont(13)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else if rows.isEmpty {
                Text("No income recorded on this day")
                    .appFont(13)
                    .foregroundStyle(.tertiary)
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

    private func loadDayDetails(for day: Date?) {
        guard let day else {
            selectedRows = []
            dayLoadError = nil
            return
        }

        do {
            let candidates = try Insights.dayContributionCandidates(on: day, in: context)
            selectedRows = app.insights.dayContributions(on: day, candidates: candidates)
            dayLoadError = nil
        } catch {
            selectedRows = []
            dayLoadError = String(localized: "Could not load income details for this day.")
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
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if showShare, dayTotal > 0 {
                        Text(percentString(ratio(row.amount, dayTotal)))
                            .appFont(11, .medium, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                if row.isHeldSlice, let hold = entry.holdUntil {
                    let full = app.toBase(entry.amount, code: entry.currencyCode)
                    Text("Slice of \(app.primaryString(full)) · held until \(DateFormat.dotted(hold))")
                        .appFont(11)
                        .foregroundStyle(.tertiary)
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

    // MARK: Helpers

    /// Horizontal share bar, scaled against the reference passed in. The track
    /// and fill are two plain rectangles clipped together to one capsule, not a
    /// smaller capsule floating inside a bigger one — two independently-rounded
    /// capsules leave a visible gap past the fill's rounded corners, so a small
    /// share reads as a stray dot instead of a sliver flush with its edge.
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

    private func ratio(_ value: Decimal, _ whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return NSDecimalNumber(decimal: value).doubleValue / NSDecimalNumber(decimal: whole).doubleValue
    }

    /// "37%" — clamped so a wild outlier can't blow the layout apart.
    private func percentString(_ fraction: Double) -> String {
        "\(Int((min(fraction, 9.99) * 100).rounded()))%"
    }
}
