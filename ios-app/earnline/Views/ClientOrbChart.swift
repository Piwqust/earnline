import SwiftUI

/// A glowing "orb" that visualizes a share breakdown — a smooth, glassy sphere
/// whose colors bleed in from the same direction as their ring segment, hugged
/// by a thin crisp percentage ring in the matching per-segment colors.
///
/// The sphere is built like a hand-made mesh gradient: a base fill in the
/// dominant client's color, then one soft radial glow per segment placed at
/// the *angular midpoint of that segment's ring arc*. So the color you see on
/// the top-right of the sphere is the same color as the arc on the top-right
/// of the ring — the sphere and ring read as one coherent object instead of a
/// muddy blur that has nothing to do with the ring around it. Overlapping,
/// lightly-blurred glows crossfade into each other smoothly the way a real
/// mesh gradient does, keeping every hue saturated where it lives and letting
/// them melt together only in the middle.
///
/// A broad top highlight and a soft bottom falloff turn the flat disc into a
/// glass sphere; a thin bright rim and a soft tinted shadow lift it off the
/// card. Purely decorative — `accessibilityHidden`, since the accompanying
/// list is the accessible source of the same breakdown.
struct ClientOrbChart: View {
    /// Segments in display order (largest first, muted "Other" last) — the
    /// same order and colors the ranked list uses, so the ring and the list's
    /// color dots always agree. `isMuted` (the gray "Other" bucket) keeps
    /// near-full strength on the ring but glows faintly inside the sphere, so a
    /// big "Other" share doesn't gray out the whole gradient.
    let segments: [(color: Color, value: Decimal, isMuted: Bool)]
    var diameter: CGFloat = 140

    @Environment(\.colorScheme) private var colorScheme

    /// How much of the muted segment's own color survives inside the sphere —
    /// low, so it reads as a faint cool region rather than a flat gray patch.
    private let mutedGlowOpacity: Double = 0.32
    private let glowOpacity: Double = 0.95

    private var ringWidth: CGFloat { diameter * 0.05 }
    private var ringGap: CGFloat { diameter * 0.012 }
    private var blobDiameter: CGFloat { diameter - 2 * (ringWidth + ringGap) }

    private var total: Decimal { segments.reduce(Decimal.zero) { $0 + $1.value } }

    /// Cumulative (start, end) fraction of the whole, 0...1, in input order —
    /// shared by the ring's arcs and the sphere's per-segment glows.
    private var slices: [(color: Color, start: Double, end: Double, isMuted: Bool)] {
        guard total > 0 else { return [(Theme.label(0.12), 0, 1, true)] }
        var cursor = 0.0
        return segments.compactMap { segment in
            let fraction = doubleValue(segment.value) / doubleValue(total)
            guard fraction > 0 else { return nil }
            let start = cursor
            cursor += fraction
            return (segment.color, start, cursor, segment.isMuted)
        }
    }

    /// The largest share's color — the sphere's base hue, so the majority of
    /// the orb reads as one dominant color like the reference.
    private var dominantColor: Color {
        segments.max { doubleValue($0.value) < doubleValue($1.value) }?.color ?? Theme.label(0.12)
    }

    /// The ring's arcs shrink slightly at both ends so neighboring colors don't
    /// touch — the thin gap visible between segments. Skipped for a single
    /// segment, which should read as one unbroken ring.
    private var ringSlices: [(color: Color, start: Double, end: Double)] {
        guard slices.count > 1 else { return slices.map { ($0.color, $0.start, $0.end) } }
        let halfGap = (2.4 / 360) / 2 // ~2.4° gap between neighboring arcs
        return slices.map { slice in
            let start = slice.start + halfGap
            let end = max(start, slice.end - halfGap)
            return (slice.color, start, end)
        }
    }

    var body: some View {
        ZStack {
            orbShadow
            blob
                .frame(width: blobDiameter, height: blobDiameter)
            ring
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    // MARK: Sphere — a base hue with per-segment glows placed at their arc angle

    /// Every segment *except* the dominant one, drawn largest→smallest so the
    /// small vivid accents land on top and stay legible. The dominant color is
    /// already the sphere's base fill, so re-drawing it as a glow would just
    /// pile an off-center bright blob on top of a field of its own color; left
    /// out, the base reads as one clean dominant hue that the accents bleed
    /// into from exactly the direction of their ring arc.
    private var glowSlices: [(color: Color, start: Double, end: Double, isMuted: Bool)] {
        let all = slices
        guard let dominantIndex = all.indices.max(by: {
            (all[$0].end - all[$0].start) < (all[$1].end - all[$1].start)
        }) else { return [] }
        return all.enumerated()
            .filter { $0.offset != dominantIndex }
            .map { $0.element }
            .sorted { ($0.end - $0.start) > ($1.end - $1.start) }
    }

    private var blob: some View {
        ZStack {
            // Crisp base edge — blurring the whole stack let the card show
            // through the softened rim as a bright halo, so only the color
            // glows are blurred while the base circle stays solid to the edge.
            Circle().fill(dominantColor)
            ZStack {
                ForEach(Array(glowSlices.enumerated()), id: \.offset) { _, slice in
                    let fraction = slice.end - slice.start
                    RadialGradient(
                        colors: [slice.color.opacity(slice.isMuted ? mutedGlowOpacity : glowOpacity), .clear],
                        center: glowCenter(forMidFraction: (slice.start + slice.end) / 2),
                        startRadius: 0,
                        // Reach scales with the segment's share, so a 3% sliver
                        // is a small pop hugging its arc while a big share
                        // spreads broadly — the dominant base stays dominant
                        // instead of being swamped by an oversized accent.
                        endRadius: blobDiameter * (0.22 + 0.5 * fraction)
                    )
                }
            }
            .blur(radius: blobDiameter * 0.06)
        }
        .clipShape(Circle())
        .saturation(1.12)
        .overlay(sphereHighlight)
        .overlay(sphereShading)
        .overlay(glassRim)
    }

    /// A soft, color-matched glow behind the whole orb — lifts it off the card
    /// instead of sitting flat.
    private var orbShadow: some View {
        Circle()
            .fill(dominantColor.opacity(colorScheme == .dark ? 0.38 : 0.24))
            .frame(width: blobDiameter, height: blobDiameter)
            .blur(radius: diameter * 0.20)
            .offset(y: diameter * 0.05)
    }

    /// A broad light source, upper area — the glossy catch-light that reads as
    /// a highlight rolling over a sphere rather than a flat blurred disc.
    private var sphereHighlight: some View {
        RadialGradient(
            colors: [.white.opacity(colorScheme == .dark ? 0.26 : 0.42), .white.opacity(0)],
            center: UnitPoint(x: 0.34, y: 0.26),
            startRadius: 0, endRadius: blobDiameter * 0.6
        )
        .blendMode(.plusLighter)
        .clipShape(Circle())
    }

    /// Falloff opposite the highlight, grounding the sphere with a touch of
    /// shadow so it doesn't read as a flat glowing circle.
    private var sphereShading: some View {
        RadialGradient(
            colors: [.black.opacity(0), .black.opacity(colorScheme == .dark ? 0.28 : 0.14)],
            center: UnitPoint(x: 0.72, y: 0.82),
            startRadius: 0, endRadius: blobDiameter * 0.7
        )
        .blendMode(.multiply)
        .clipShape(Circle())
    }

    /// A thin bright rim, strongest along the top edge — the glassy edge that
    /// replaces the old hard white border and gives the sphere its polish.
    private var glassRim: some View {
        Circle().strokeBorder(
            LinearGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.22 : 0.4), .white.opacity(0)],
                startPoint: .top, endPoint: .center
            ),
            lineWidth: 1
        )
    }

    // MARK: Ring — a crisp percentage ring hugging the sphere

    private var ring: some View {
        ZStack {
            ForEach(Array(ringSlices.enumerated()), id: \.offset) { _, slice in
                RingArc(start: slice.start, end: slice.end, inset: ringWidth / 2)
                    .stroke(slice.color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
            }
        }
    }

    /// Unit-point center for a segment's glow: placed toward the edge at the
    /// same angle as the segment's ring arc (0 at 12 o'clock, sweeping
    /// clockwise), so sphere color and ring color line up direction-for-direction.
    private func glowCenter(forMidFraction fraction: Double) -> UnitPoint {
        let theta = fraction * 2 * .pi
        let radius = 0.33
        return UnitPoint(x: 0.5 + radius * sin(theta),
                         y: 0.5 - radius * cos(theta))
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

/// An open arc (no center point) at a fixed `inset` from the frame's edge —
/// the ring's per-segment stroke, starting at 12 o'clock and sweeping
/// clockwise as `start`/`end` (fractions 0...1 of the whole circle) increase.
private struct RingArc: Shape {
    var start: Double
    var end: Double
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - inset
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(start * 360 - 90),
                    endAngle: .degrees(end * 360 - 90),
                    clockwise: false)
        return path
    }
}
