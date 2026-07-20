import SwiftUI

/// The floating glass header from the Figma: two side-by-side cards — "Earned
/// in <month>" with the running total on the left, and a "Stats" card with a
/// faded sparkline and the month-over-month change on the right. Tapping the
/// Stats card opens the full Insights sheet.
struct SummaryCards: View {
    @Environment(AppModel.self) private var app
    let month: Date
    let total: Decimal
    /// Earned base-currency totals ending at `month`, oldest first — drives the
    /// sparkline and the growth figure so both track the displayed month.
    let trend: [Decimal]
    let onOpenStats: () -> Void

    /// Tracks the prior total for value-transition direction when a user edits
    /// a line or switches an explicit display context.
    @State private var previousTotal: Decimal = 0

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 12) {
                earnedCard
                statsCard
            }
        }
        .frame(height: 112)
        .onChange(of: total) { oldValue, _ in previousTotal = oldValue }
    }

    // MARK: Earned

    private var earnedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            earnedTitle
            Spacer(minLength: 12)
            MoneyAmountText(baseAmount: total,
                            size: 20, weight: .medium,
                            color: Theme.label,
                            countsDownFrom: previousTotal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.summary))
    }

    /// "Earned in July". The split is derived from the localized "Earned in %@"
    /// template (the month is last in every supported locale), so there's no
    /// separate label string to translate.
    private var earnedTitle: some View {
        let parts = Self.earnedTitleParts
        return HStack(spacing: 0) {
            if !parts.prefix.isEmpty { Text(parts.prefix) }
            Text(DateFormat.month(month))
            if !parts.suffix.isEmpty { Text(parts.suffix) }
        }
        .appFont(14, .medium)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// The localized "Earned in %@" split around its month placeholder.
    private static var earnedTitleParts: (prefix: String, suffix: String) {
        let template = String(localized: "Earned in %@")
        guard let range = template.range(of: "%@") else { return (template, "") }
        return (String(template[..<range.lowerBound]), String(template[range.upperBound...]))
    }

    // MARK: Stats

    private var statsCard: some View {
        Button(action: onOpenStats) {
            ZStack(alignment: .bottomLeading) {
                Sparkline(values: trend.map(doubleValue))
                    .padding(.top, 22)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Stats")
                        .appFont(14, .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 12)
                    Text(growthText)
                        .appFont(20, .medium, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(Theme.label)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.Radius.summary))
            .contentShape(.rect(cornerRadius: Theme.Radius.summary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stats")
        .accessibilityValue(growthText)
        .accessibilityHint(Text("Opens insights"))
        .accessibilityIdentifier("ledger.stats")
    }

    /// This month against the one before it. Nil when there's no prior baseline
    /// to grow from, in which case the card just shows a dash.
    private var growthFraction: Double? {
        guard trend.count >= 2 else { return nil }
        let latest = doubleValue(trend[trend.count - 1])
        let prior = doubleValue(trend[trend.count - 2])
        guard prior > 0 else { return nil }
        return latest / prior - 1
    }

    private var growthText: String {
        // A partial calendar month is not comparable to the preceding whole
        // month. Showing its raw percentage made a healthy month look like a
        // dramatic collapse until the final day arrived.
        guard !Calendar.current.isDate(month, equalTo: .now, toGranularity: .month) else {
            return String(localized: "So far")
        }
        guard let fraction = growthFraction else { return "—" }
        // Clamp so a wild spike (a first invoice after a dry month) can't blow
        // the card's width apart.
        let pct = Int((min(fraction, 9.99) * 100).rounded())
        return "\(pct >= 0 ? "+" : "")\(pct)%"
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

/// A decorative monochrome area sparkline — the peaks-and-valleys line behind
/// the Stats headline. The line is a smooth Catmull-Rom curve (not raw
/// polyline segments) with a soft gradient fill and a dot on the latest point.
/// It updates as static content as the ledger crosses a month, avoiding a
/// path-morph animation in the hot scroll path.
private struct Sparkline: View {
    var values: [Double]

    /// Left-to-right fade shared by the stroke and its fill — the oldest point
    /// dissolves to nothing, easing in quickly so only the most recent stretch
    /// of the trend reads as solid.
    private var horizontalFade: Gradient {
        Gradient(stops: [
            .init(color: Theme.label(0), location: 0),
            .init(color: Theme.label(0.28), location: 0.32),
            .init(color: Theme.label(0.6), location: 1),
        ])
    }

    var body: some View {
        ZStack {
            // Soft fill under the curve, faded on both axes: brightest just
            // beneath the line's solid (recent) end, dissolving to nothing at
            // the baseline and toward the oldest point on the left.
            SparkArea(values: values)
                .fill(
                    LinearGradient(colors: [Theme.label(0.18), Theme.label(0.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .mask(
                    LinearGradient(gradient: horizontalFade,
                                   startPoint: .leading, endPoint: .trailing)
                )

            // The curve itself dissolves toward the past (left) and solidifies
            // toward the present (right), so the eye lands on where the trend
            // ends up.
            SparkCurve(values: values)
                .stroke(
                    LinearGradient(gradient: horizontalFade,
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

            // A dot anchors the latest value, with a faint halo to lift it off
            // the line.
            SparkDot(values: values, radius: 5.5).fill(Theme.label(0.12))
            SparkDot(values: values, radius: 2.5).fill(Theme.label(0.7))
        }
    }
}

// MARK: Sparkline geometry

/// Maps the values onto the box, insetting every edge so neither a peak nor the
/// endpoint dot (radius 5.5 + halo) clips against an edge or the card's corner.
private func sparkPoints(_ values: [Double], in size: CGSize) -> [CGPoint] {
    guard values.count >= 2 else { return [] }
    let lo = values.min() ?? 0
    let hi = values.max() ?? 1
    let span = hi - lo
    let topInset: CGFloat = 7
    let bottomInset: CGFloat = 6
    let leadingInset: CGFloat = 3
    let trailingInset: CGFloat = 10   // clears the endpoint dot + halo
    let usableH = max(size.height - topInset - bottomInset, 1)
    let usableW = max(size.width - leadingInset - trailingInset, 1)
    let stepX = usableW / CGFloat(values.count - 1)
    return values.enumerated().map { index, value in
        let norm = span > 0 ? (value - lo) / span : 0.5
        return CGPoint(x: leadingInset + CGFloat(index) * stepX,
                       y: topInset + usableH * (1 - CGFloat(norm)))
    }
}

/// A flowing curve through the points using Catmull-Rom control points,
/// converted to cubic Béziers — smooth without overshooting wildly.
private func sparkSmoothLine(_ pts: [CGPoint]) -> Path {
    Path { path in
        guard pts.count >= 2 else { return }
        path.move(to: pts[0])
        for i in 0..<pts.count - 1 {
            let p0 = i == 0 ? pts[i] : pts[i - 1]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }
}

private struct SparkCurve: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        let pts = sparkPoints(values, in: rect.size)
        guard pts.count >= 2 else { return Path() }
        return sparkSmoothLine(pts)
    }
}

private struct SparkArea: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        let pts = sparkPoints(values, in: rect.size)
        guard pts.count >= 2 else { return Path() }
        var path = sparkSmoothLine(pts)
        path.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: rect.height))
        path.addLine(to: CGPoint(x: pts[0].x, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct SparkDot: Shape {
    let values: [Double]
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let last = sparkPoints(values, in: rect.size).last else { return Path() }
        return Path(ellipseIn: CGRect(x: last.x - radius, y: last.y - radius,
                                      width: radius * 2, height: radius * 2))
    }
}
