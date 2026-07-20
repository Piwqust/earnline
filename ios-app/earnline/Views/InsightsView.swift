import SwiftUI
import SwiftData
import Charts

/// Income at a glance. Ledger models are captured once into a Sendable input and
/// aggregated off the main actor, keeping sheet presentation and interaction
/// independent from the size of the ledger.
struct InsightsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Client.sortIndex) private var clients: [Client]
    @Query(sort: \Heading.date, order: .reverse) private var headings: [Heading]
    @Query(sort: \MonthReview.monthStart, order: .reverse) private var monthReviews: [MonthReview]

    @State private var windowMonths = 3
    @State private var selectedDay: Date?
    @State private var chartSelection: Date?
    @State private var dashboard: InsightsDashboardSnapshot?
    @State private var isRefreshing = false
    @State private var dashboardError: String?
    @State private var dashboardReloadToken = 0
    @State private var dashboardDataRevision = 0
    @State private var personalReportSnapshot: ReportSnapshot?
    @State private var personalReportScope: ReportScope?
    @State private var reportReviewOverride: ReportMonthReview?
    @State private var presentsPersonalReportPreview = false

    private var calendar: Calendar { .current }

    /// Every saved mutation invalidates the private-model-actor snapshot. This
    /// avoids bringing the entire entry query onto SwiftUI's render path merely
    /// to detect an update.
    private var dashboardRevision: DashboardRevision {
        DashboardRevision(
            windowMonths: windowMonths,
            dataRevision: dashboardDataRevision,
            reloadToken: dashboardReloadToken,
            baseCurrencyCode: app.baseCurrencyCode,
            secondaryCurrencyCode: app.secondaryCurrencyCode,
            rate: app.rate
        )
    }

    private var trendChartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 280 : 210
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                periodPicker

                dashboardState
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
        .accessibilityIdentifier("insights.sheet")
        .task(id: dashboardRevision) { await loadDashboard() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            dashboardDataRevision &+= 1
        }
        .sheet(isPresented: $presentsPersonalReportPreview) {
            if let personalReportSnapshot {
                ReportPreviewView(
                    snapshot: personalReportSnapshot,
                    onCloseMonth: closePersonalReportMonth,
                    onReopenMonth: reopenPersonalReportMonth,
                    snapshotFactory: refreshedPersonalReportSnapshot
                )
            }
        }
    }

    private struct DashboardRevision: Hashable {
        let windowMonths: Int
        let dataRevision: Int
        let reloadToken: Int
        let baseCurrencyCode: String
        let secondaryCurrencyCode: String
        let rate: Double
    }

    @MainActor
    private func loadDashboard() async {
        isRefreshing = true
        dashboardError = nil
        let requestedWindow = windowMonths
        // Let the sheet commit its first frame before the private model actor
        // fetches and faults the ledger. The SwiftUI main actor never walks all
        // rows just to open this sheet.
        await Task.yield()
        guard !Task.isCancelled, requestedWindow == windowMonths else { return }
        let loader = InsightsDashboardLoader(modelContainer: context.container)
        do {
            let snapshot = try await loader.load(
                windowMonths: requestedWindow,
                converter: app.converter
            )
            guard !Task.isCancelled, requestedWindow == windowMonths else { return }
            withAnimation(.smooth(duration: 0.22)) {
                dashboard = snapshot
                isRefreshing = false
            }
        } catch is CancellationError {
            // A newer revision is already loading. Keep its loading state.
        } catch {
            guard !Task.isCancelled, requestedWindow == windowMonths else { return }
            dashboardError = error.localizedDescription
            isRefreshing = false
        }
    }

    @ViewBuilder
    private var dashboardState: some View {
        if let dashboard, dashboard.windowMonths == windowMonths {
            dashboardContent(dashboard)
            if dashboardError != nil {
                dashboardRefreshError
            }
        } else if dashboardError != nil {
            dashboardErrorState
        } else {
            dashboardSkeleton
        }
    }

    @ViewBuilder
    private func dashboardContent(_ snapshot: InsightsDashboardSnapshot) -> some View {
        let map = snapshot.dailyEarnings
        let maxDaily = map.values.max() ?? .zero
        let heatTotal = map.values.reduce(Decimal.zero, +)

        shareMonthlyReportAction(snapshot)

        if snapshot.unsupportedCurrencyCount > 0 {
            Label("\(snapshot.unsupportedCurrencyCount) line(s) are excluded from these totals because no conversion rate is set.",
                  systemImage: "exclamationmark.triangle.fill")
                .appFont(13)
                .foregroundStyle(Theme.statusProgress)
                .accessibilityLabel("\(snapshot.unsupportedCurrencyCount) lines are excluded from consolidated totals because no conversion rate is set")
        }

        EarningsHeatmapCard(clients: clients,
                            map: map,
                            maxDaily: maxDaily,
                            heatTotal: heatTotal,
                            months: snapshot.months,
                            selectedDay: $selectedDay)
            .id(snapshot.windowMonths)

        VStack(alignment: .leading, spacing: 0) {
            CardHeader("Monthly income")
            monthlyIncomeCard(snapshot.monthlyIncome)
        }

        statsCard(snapshot)

        if !snapshot.clientTotals.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader("Top clients")
                topClientsCard(snapshot.clientTotals)
            }
        }
    }

    private func shareMonthlyReportAction(_ dashboard: InsightsDashboardSnapshot) -> some View {
        let month = selectedPoint(dashboard.monthlyIncome)?.month
            ?? dashboard.monthlyIncome.last?.month
            ?? .now
        return Button {
            let scope = ReportScope.month(containing: month)
            personalReportScope = scope
            reportReviewOverride = nil
            personalReportSnapshot = makePersonalReport(scope: scope)
            presentsPersonalReportPreview = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label("Share monthly report", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                Text(DateFormat.monthAndYear(month))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("Previews PNG cards before opening the Share Sheet")
        .accessibilityIdentifier("insights.report.share")
    }

    private var dashboardSkeleton: some View {
        ChromeCard {
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing insights")
                    .appFont(13, .medium)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
        .accessibilityIdentifier("insights.loading")
    }

    private var dashboardErrorState: some View {
        ChromeCard {
            ContentUnavailableView {
                Label("Couldn’t load insights", systemImage: "chart.line.downtrend.xyaxis")
            } description: {
                Text("Your ledger is unchanged. Try again to calculate this view.")
            } actions: {
                Button("Try again", action: retryDashboardLoad)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .frame(maxWidth: .infinity, minHeight: 190)
        }
        .accessibilityIdentifier("insights.error")
    }

    private var dashboardRefreshError: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.statusProgress)
            Text("Showing the last calculated insights.")
                .appFont(13)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Retry", action: retryDashboardLoad)
                .appFont(13, .semibold)
        }
        .accessibilityIdentifier("insights.refreshError")
    }

    private func retryDashboardLoad() {
        dashboardReloadToken &+= 1
    }

    // MARK: Shareable monthly report

    /// Copy report input only after the user explicitly asks for a report.
    /// The builder then owns immutable values; the image renderer never reads
    /// live SwiftData models while it draws a card.
    private func makePersonalReport(scope: ReportScope) -> ReportSnapshot {
        let input = ReportSnapshotInput(
            clients: clients,
            headings: headings,
            monthReviews: personalReportMonthReviews,
            converter: app.converter
        )
        return ReportSnapshotBuilder(input: input).snapshot(scope: scope, audience: .personal)
    }

    private var personalReportMonthReviews: [ReportMonthReview] {
        var reviews = monthReviews.compactMap { review -> ReportMonthReview? in
            guard !review.isDeleted else { return nil }
            return ReportMonthReview(
                monthStart: review.monthStart,
                note: review.note,
                closedAt: review.closedAt
            )
        }
        if let reportReviewOverride {
            reviews.removeAll {
                Calendar.current.isDate($0.monthStart,
                                        equalTo: reportReviewOverride.monthStart,
                                        toGranularity: .month)
            }
            reviews.append(reportReviewOverride)
        }
        return reviews
    }

    private func refreshedPersonalReportSnapshot() -> ReportSnapshot {
        guard let scope = personalReportScope else {
            return personalReportSnapshot
                ?? makePersonalReport(scope: .month(containing: .now))
        }
        return makePersonalReport(scope: scope)
    }

    private func closePersonalReportMonth(note: String) -> String? {
        guard let scope = personalReportScope, scope.isMonth else {
            return String(localized: "This report is not a calendar month.")
        }
        do {
            let review = try MonthReviewStore.close(
                monthContaining: scope.period().start,
                note: note,
                in: context
            )
            if let error = app.save(context) { return error }
            reportReviewOverride = ReportMonthReview(
                monthStart: review.monthStart,
                note: review.note,
                closedAt: review.closedAt
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func reopenPersonalReportMonth() -> String? {
        guard let scope = personalReportScope, scope.isMonth else {
            return String(localized: "This report is not a calendar month.")
        }
        do {
            guard let review = try MonthReviewStore.reopen(
                monthContaining: scope.period().start,
                in: context
            ) else {
                return nil
            }
            if let error = app.save(context) { return error }
            reportReviewOverride = ReportMonthReview(
                monthStart: review.monthStart,
                note: review.note,
                closedAt: review.closedAt
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Period

    private var periodPicker: some View {
        // Labels match the actual windows (3/6/12 months) — the Health-style
        // "Week/Month/Year" wording lied about what was charted.
        Picker("", selection: $windowMonths) {
            Text("3M").tag(3)
            Text("6M").tag(6)
            Text("1Y").tag(12)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Time range")
        .overlay(alignment: .trailing) {
            if isRefreshing, dashboard != nil {
                ProgressView().controlSize(.mini).padding(.trailing, 8).allowsHitTesting(false)
            }
        }
        .onChange(of: windowMonths) {
            selectedDay = nil
            chartSelection = nil
            dashboardError = nil
        }
    }

    // MARK: Monthly income chart

    private func selectedPoint(_ data: [InsightsDashboardSnapshot.MonthPoint])
        -> InsightsDashboardSnapshot.MonthPoint? {
        guard let chartSelection else { return nil }
        return data.first { calendar.isDate($0.month, equalTo: chartSelection, toGranularity: .month) }
    }

    private func monthlyIncomeCard(_ data: [InsightsDashboardSnapshot.MonthPoint]) -> some View {
        let selected = selectedPoint(data)
        let hasData = data.contains { $0.total > 0 }
        let highlighted = selected ?? data.last

        return ChromeCard {
            Chart {
                ForEach(data) { point in
                    AreaMark(
                        x: .value("Month", point.month, unit: .month),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Income", doubleValue(point.total))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [app.accentColor.opacity(0.18), app.accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Income", doubleValue(point.total))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(app.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(DateFormat.monthAndYear(point.month))
                    .accessibilityValue(app.primaryString(point.total))
                }

                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.quaternary)
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if let selected {
                    RuleMark(x: .value("Month", selected.month, unit: .month))
                        .foregroundStyle(.quaternary)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, spacing: 7,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            monthlyIncomeCallout(selected)
                        }
                }

                if let highlighted {
                    PointMark(
                        x: .value("Highlighted month", highlighted.month, unit: .month),
                        y: .value("Highlighted income", doubleValue(highlighted.total))
                    )
                    .foregroundStyle(app.accentColor)
                    .symbolSize(55)
                }
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactAmount(amount))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: max(data.count / 6, 1))) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityIdentifier("insights.monthlyIncomeChart")
    }

    private func monthlyIncomeCallout(_ point: InsightsDashboardSnapshot.MonthPoint) -> some View {
        let change = point.change
        let up = change >= 0
        return VStack(spacing: 2) {
            Text(app.primaryString(point.total))
                .appFont(12, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
            Text(DateFormat.monthAndYear(point.month))
                .appFont(9)
                .foregroundStyle(.secondary)
            Text("\(up ? "+" : "−")\(app.primaryString(abs(change))) \(String(localized: "vs previous month"))")
                .appFont(9, .medium, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(up ? Theme.green : Theme.statusCanceled)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.surface, in: .rect(cornerRadius: 9))
        .shadow(color: Theme.label(0.10), radius: 5, y: 2)
    }

    // MARK: Stats — three headline figures in one card

    private func statsCard(_ snapshot: InsightsDashboardSnapshot) -> some View {
        ChromeCard {
            HStack(alignment: .top, spacing: 8) {
                heroStat("This year", value: app.primaryString(snapshot.yearToDateTotal.rounded()))
                heroStat("Best month", value: snapshot.bestMonth.map { app.primaryString($0.total.rounded()) } ?? "—")
                heroStat("Avg / month", value: app.primaryString(snapshot.averageMonth.rounded()))
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
        }
    }

    private func heroStat(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .appFont(13)
                .foregroundStyle(.secondary)
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

    // MARK: Top clients — orb first, ranked breakdown below

    private func topClientsCard(_ breakdown: [InsightsDashboardSnapshot.ClientTotal]) -> some View {
        let total = breakdown.reduce(Decimal.zero) { $0 + $1.total }
        let shown = Array(breakdown.prefix(4))
        let othersTotal = breakdown.dropFirst(4).reduce(Decimal.zero) { $0 + $1.total }
        let segments = shown.map { (color: Color(hex: $0.colorHex), value: $0.total, isMuted: false) }
            + (othersTotal > 0 ? [(color: Theme.label(0.3), value: othersTotal, isMuted: true)] : [])

        return ChromeCard {
            VStack(spacing: 22) {
                ClientOrbChart(segments: segments, diameter: 154)
                    .accessibilityIdentifier("insights.clientOrb")

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Client share")
                        Spacer()
                        Text("Income")
                    }
                    .appFont(12, .semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 40)
                    .padding(.bottom, 6)

                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                        clientBreakdownRow(rank: index + 1,
                                           name: row.name,
                                           total: row.total,
                                           color: Color(hex: row.colorHex),
                                           whole: total)
                        if index < shown.count - 1 || othersTotal > 0 { ChromeDivider(inset: 0) }
                    }
                    if othersTotal > 0 {
                        clientBreakdownRow(rank: nil,
                                           name: String(localized: "Other clients"),
                                           total: othersTotal,
                                           color: Theme.label(0.3),
                                           whole: total)
                    }
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("insights.topClients")
    }

    /// A ranked, finance-native row. Exact values stay typographically aligned
    /// while the short track makes relative share visible without asking the
    /// decorative orb to carry all of the interpretation work.
    private func clientBreakdownRow(
        rank: Int?,
        name: String,
        total: Decimal,
        color: Color,
        whole: Decimal
    ) -> some View {
        let share = ratio(total, whole)
        return HStack(alignment: .top, spacing: 12) {
            Text(rank.map(String.init) ?? "•••")
                .appFont(12, .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 9) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        clientName(name)
                        Spacer(minLength: 8)
                        clientAmount(total)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        clientName(name)
                        clientAmount(total)
                    }
                }

                HStack(spacing: 10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fillQuaternary)
                            Capsule()
                                .fill(color)
                                .frame(width: max(4, proxy.size.width * CGFloat(share)))
                        }
                    }
                    .frame(height: 5)

                    Text(percentString(share))
                        .appFont(12, .semibold, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 56 : 40,
                               alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    private func clientName(_ name: String) -> some View {
        Text(name)
            .appFont(15, .semibold)
            .foregroundStyle(Theme.label)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func clientAmount(_ total: Decimal) -> some View {
        Text(app.primaryString(total))
            .appFont(15, .semibold, design: .rounded)
            .monospacedDigit()
            .foregroundStyle(Theme.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
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

    /// Compact currency-aware chart label, e.g. "1k" or "2M".
    private func compactAmount(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return "\(CurrencyFormatter.grouped(Decimal(magnitude / 1_000_000), code: app.baseCurrencyCode))M"
        }
        if magnitude >= 1000 {
            return "\(CurrencyFormatter.grouped(Decimal(magnitude / 1000), code: app.baseCurrencyCode))k"
        }
        return CurrencyFormatter.grouped(Decimal(magnitude), code: app.baseCurrencyCode)
    }
}
