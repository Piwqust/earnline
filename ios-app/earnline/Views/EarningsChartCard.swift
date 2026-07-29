import SwiftUI
import UIKit
import Charts

/// The app's standardized monthly-earnings chart card: a stat header
/// (eyebrow, headline figure, period line) over a scrubbable trend in the
/// Finimize research-chart style — a smooth line riding a diagonal-hatched
/// band, each point's value in a quiet row along the top (closed off by a
/// dotted separator), an endpoint dot, and no axis chrome beyond a quiet
/// month row. Scrubbing drops a dotted crosshair with a dark value flag and
/// swaps the header to the touched month; the flag clamps to the chart
/// bounds so it never clips against the card edge. An optional segmented
/// range control sits above the header.
/// Monotone interpolation, not Catmull-Rom: the curve stays smooth without
/// inventing dips and overshoots between real monthly figures.
struct EarningsChartCard: View {
    struct Point: Identifiable {
        let month: Date
        let total: Decimal
        /// The prior month's total when a comparison base exists; drives the
        /// "vs previous month" delta while scrubbing.
        let previousTotal: Decimal?
        var id: Date { month }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let points: [Point]
    let tint: Color
    /// Bound charted window in months (3/6/12). When set, a segmented range
    /// control appears and the chart shows the trailing `window` points; nil
    /// charts every point with no control.
    var window: Binding<Int>?
    var emptyText: LocalizedStringKey = "No earned income in this period"
    /// A preview-only reveal mask for the account tour. Nil preserves the
    /// production chart's existing, fully rendered behaviour.
    var drawProgress: CGFloat? = nil
    /// Internal-only timing for the account tour's measured chart reveal.
    /// Production callers leave this nil and retain the existing timing.
    var previewDrawDuration: TimeInterval? = nil

    @State private var selection: Date?

    private var calendar: Calendar { .current }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 240 : 190
    }

    private var visiblePoints: [Point] {
        guard let window = window?.wrappedValue else { return points }
        return Array(points.suffix(window))
    }

    private var selectedPoint: Point? {
        guard let selection else { return nil }
        return visiblePoints.first {
            calendar.isDate($0.month, equalTo: selection, toGranularity: .month)
        }
    }

    var body: some View {
        ChromeCard {
            VStack(alignment: .leading, spacing: 14) {
                if let window {
                    rangeControl(window)
                }
                header
                chart
            }
            .padding(16)
        }
        .sensoryFeedback(.selection, trigger: selectedPoint?.id)
        .onChange(of: window?.wrappedValue) {
            selection = nil
        }
    }

    // MARK: Range control — local to the card, the Health placement

    private func rangeControl(_ window: Binding<Int>) -> some View {
        Picker("", selection: window.animation(.smooth(duration: 0.3))) {
            Text(verbatim: "3M").tag(3)
            Text(verbatim: "6M").tag(6)
            Text(verbatim: "1Y").tag(12)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Chart time range")
    }

    // MARK: Stat header — swaps to the scrubbed month, Health-style

    private var header: some View {
        let visible = visiblePoints
        let selected = selectedPoint
        let headline = selected?.total
            ?? visible.reduce(Decimal.zero) { $0 + $1.total }

        return VStack(alignment: .leading, spacing: 2) {
            Group {
                if let selected {
                    Text(verbatim: DateFormat.monthAndYear(selected.month))
                } else {
                    Text("Total")
                }
            }
            .appFont(11, .semibold)
            .textCase(.uppercase)
            .kerning(0.4)
            .foregroundStyle(.secondary)

            Text(app.primaryString(headline.rounded()))
                .appFont(28, .bold, design: .rounded, relativeTo: .title)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())

            subtitle(selected: selected, visible: visible)
        }
        .animation(.snappy(duration: 0.22), value: selectedPoint?.id)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func subtitle(selected: Point?, visible: [Point]) -> some View {
        if let selected, let previous = selected.previousTotal {
            let change = selected.total - previous
            let up = change >= 0
            Text("\(up ? "+" : "−")\(app.primaryString(abs(change))) \(String(localized: "vs previous month"))")
                .appFont(12, .medium, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(up ? Theme.green : Theme.statusCanceled)
        } else if let first = visible.first, let last = visible.last {
            Text(verbatim: first.month == last.month
                 ? DateFormat.monthAndYear(first.month)
                 : "\(DateFormat.monthAndYear(first.month)) – \(DateFormat.monthAndYear(last.month))")
                .appFont(12)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chart: some View {
        let visible = visiblePoints
        let selected = selectedPoint
        let hasData = visible.contains { $0.total > 0 }
        let values = visible.map { doubleValue($0.total) }
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        // The hatched ribbon rides the line rather than filling to zero, so
        // the y-domain can hug the data and small month-to-month moves stay
        // visible. Thickness follows the visible spread, with a floor so a
        // flat run still shows a band instead of a bare line.
        let band = max(maxValue - minValue, maxValue * 0.25) * 0.6

        let chart = Chart {
            ForEach(visible) { point in
                if band > 0 {
                    AreaMark(
                        x: .value("Month", point.month, unit: .month),
                        yStart: .value("Band low", max(0, doubleValue(point.total) - band / 2)),
                        yEnd: .value("Band high", doubleValue(point.total) + band / 2)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(ImagePaint(image: Self.stripeTexture(for: tint)))
                }

                LineMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value("Income", doubleValue(point.total))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(DateFormat.monthAndYear(point.month))
                .accessibilityValue(app.primaryString(point.total))
            }

            if let selected {
                RuleMark(x: .value("Month", selected.month, unit: .month))
                    .foregroundStyle(Theme.label(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    .annotation(
                        position: .top,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        scrubFlag(for: selected)
                    }
            }

            // The touched month while scrubbing; the series endpoint at rest —
            // the Finimize "where the line is now" dot, punched out of the
            // band with a background-colored halo.
            if let marker = selected ?? visible.last {
                PointMark(
                    x: .value("Month", marker.month, unit: .month),
                    y: .value("Income", doubleValue(marker.total))
                )
                .symbol {
                    ZStack {
                        Circle().fill(Theme.background).frame(width: 15, height: 15)
                        Circle().fill(tint).frame(width: 9, height: 9)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis(.hidden)
        .chartXAxis {
            // The value row: each point's figure sits above its month, so
            // rises and falls can be read as numbers, not just slope.
            AxisMarks(position: .top, values: labeledMonths(in: visible)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self),
                       let point = visible.first(where: {
                           calendar.isDate($0.month, equalTo: date, toGranularity: .month)
                       }) {
                        Text(Self.compactValue(doubleValue(point.total)))
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.label(0.45))
                            // Never truncate to "1…" at the plot edge; the
                            // card's padding absorbs the small overhang.
                            .fixedSize()
                            .padding(.bottom, 5)
                    }
                }
            }
            AxisMarks(values: .stride(by: .month)) { value in
                // Text inside the label closure, not the format-parameter
                // form: the bare form resolves `.secondary` against the
                // chart's accent tint, turning the month row accent-colored.
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        // A year of bars gets Health's single-letter months;
                        // shorter windows have room for abbreviated names.
                        Text(date, format: visible.count > 6
                             ? .dateTime.month(.narrow)
                             : .dateTime.month(.abbreviated))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.label(0.55))
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            // The dotted rule that closes off the value row, exactly at the
            // top edge of the plot.
            plot.overlay(alignment: .top) {
                HorizontalDashes()
                    .stroke(Theme.label(0.16), style: StrokeStyle(lineWidth: 1, dash: [2, 3.5]))
                    .frame(height: 1)
            }
        }
        // iOS 27's native chart-selection recognizer can decline a drag when
        // this chart is embedded in a sheet scroll view. Translate the drag
        // through the chart proxy instead, keeping the selection dependable
        // without changing the chart's accessible data marks.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plotArea = geometry[plotFrame]
                    Rectangle()
                        .fill(.clear)
                        .contentShape(.rect)
                        .frame(width: plotArea.width, height: plotArea.height)
                        .position(x: plotArea.midX, y: plotArea.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - plotArea.origin.x
                                    guard x >= 0,
                                          x <= plotArea.width,
                                          let date: Date = proxy.value(atX: x) else { return }
                                    selection = date
                                }
                        )
                }
            }
        }
        .frame(height: chartHeight)
        .overlay {
            if !hasData {
                Text(emptyText)
                    .appFont(11)
                    .foregroundStyle(.tertiary)
            }
        }

        if let drawProgress {
            chart
                .mask(alignment: .leading) {
                    Rectangle()
                        .scaleEffect(x: min(max(drawProgress, 0), 1), anchor: .leading)
                }
                .animation(
                    .easeInOut(duration: previewDrawDuration ?? 0.72),
                    value: drawProgress
                )
        } else {
            chart
        }
    }

    // MARK: Scrub flag — the dark value pill riding the dotted crosshair

    private func scrubFlag(for point: Point) -> some View {
        VStack(spacing: 0) {
            Text(app.primaryString(point.total.rounded()))
                .appFont(12, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.label, in: Capsule())
            FlagTail()
                .fill(Theme.label)
                .frame(width: 10, height: 5)
        }
        .accessibilityHidden(true) // the header already announces the scrubbed month
    }

    // MARK: Helpers

    /// The months that get a figure in the top value row. Everything fits up
    /// to ~7 points; a year of months labels every other one, anchored to the
    /// newest point so the latest figure is always present.
    private func labeledMonths(in visible: [Point]) -> [Date] {
        let stride = visible.count > 7 ? 2 : 1
        return visible.indices
            .filter { (visible.count - 1 - $0) % stride == 0 }
            .map { visible[$0].month }
    }

    /// "450", "1.2K", "45K", "1.1M" — the value row needs figures narrow
    /// enough to sit twelve abreast, so thousands compress and the currency
    /// symbol stays with the headline above.
    private static func compactValue(_ value: Double) -> String {
        func trimmed(_ scaled: Double) -> String {
            let tenth = (scaled * 10).rounded() / 10
            return tenth == tenth.rounded()
                ? String(Int(tenth))
                : String(format: "%.1f", tenth)
        }
        let magnitude = abs(value)
        if magnitude >= 1_000_000 { return trimmed(value / 1_000_000) + "M" }
        if magnitude >= 1_000 { return trimmed(value / 1_000) + "K" }
        return String(Int(value.rounded()))
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// One tile of the diagonal-hatch band fill, tinted and cached per color —
    /// `ImagePaint` repeats it along the ribbon under the trend line. Rendered
    /// once per tint, not per body evaluation.
    @MainActor private static var textureCache: [String: Image] = [:]

    @MainActor
    private static func stripeTexture(for tint: Color) -> Image {
        let color = UIColor(tint)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let key = "\(red)-\(green)-\(blue)-\(alpha)"
        if let cached = textureCache[key] { return cached }

        let tile: CGFloat = 14
        let spacing: CGFloat = 7 // divides the tile evenly so the pattern repeats seamlessly
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: tile, height: tile)).image { _ in
            let path = UIBezierPath()
            var x: CGFloat = -tile
            while x <= tile * 2 {
                path.move(to: CGPoint(x: x, y: tile))
                path.addLine(to: CGPoint(x: x + tile, y: 0))
                x += spacing
            }
            path.lineWidth = 2.6
            color.withAlphaComponent(0.22).setStroke()
            path.stroke()
        }
        let image = Image(uiImage: rendered)
        textureCache[key] = image
        return image
    }
}

/// A single dashed horizontal line; `Divider` can't dash.
private struct HorizontalDashes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The small downward pointer under the scrub flag.
private struct FlagTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
