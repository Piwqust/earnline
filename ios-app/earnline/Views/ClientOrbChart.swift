import SwiftUI

/// A proportional glass orb whose color fields line up with the surrounding
/// client-share segments. The ranked list is the accessible source of the same
/// values, so this visualization stays decorative.
struct ClientOrbChart: View {
    let segments: [(color: Color, value: Decimal, isMuted: Bool)]
    var diameter: CGFloat = 154

    @Environment(\.colorScheme) private var colorScheme

    private let mutedGlowOpacity = 0.32
    private let glowOpacity = 0.95

    /// The ring is deliberately fine and separated from the sphere. Its job is
    /// to explain proportions, not to become a second heavy circle.
    private var ringWidth: CGFloat { max(3, diameter * 0.023) }
    private var ringGap: CGFloat { diameter * 0.038 }
    private var blobDiameter: CGFloat { diameter - 2 * (ringWidth + ringGap) }
    private var total: Decimal { segments.reduce(Decimal.zero) { $0 + $1.value } }

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

    /// Wider angular breathing room makes adjacent shares readable even when
    /// their colors are visually close. A single share remains a closed ring.
    private var ringSlices: [(color: Color, start: Double, end: Double)] {
        guard slices.count > 1 else { return slices.map { ($0.color, $0.start, $0.end) } }
        let halfGap = (5.5 / 360) / 2
        return slices.compactMap { slice in
            let available = slice.end - slice.start
            let adaptiveHalfGap = min(halfGap, available * 0.22)
            let start = slice.start + adaptiveHalfGap
            let end = slice.end - adaptiveHalfGap
            guard end > start else { return nil }
            return (slice.color, start, end)
        }
    }

    private var dominantColor: Color {
        segments.max { doubleValue($0.value) < doubleValue($1.value) }?.color ?? Theme.label(0.12)
    }

    private var glowSlices: [(color: Color, start: Double, end: Double, isMuted: Bool)] {
        guard let dominantIndex = slices.indices.max(by: {
            (slices[$0].end - slices[$0].start) < (slices[$1].end - slices[$1].start)
        }) else { return [] }
        return slices.enumerated()
            .filter { $0.offset != dominantIndex }
            .map(\.element)
            .sorted { ($0.end - $0.start) > ($1.end - $1.start) }
    }

    var body: some View {
        ZStack {
            orbShadow
            blob.frame(width: blobDiameter, height: blobDiameter)
            ring
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// Restores the earlier data-shaped core: every field grows from its own
    /// segment angle and its reach follows that segment's actual share.
    private var blob: some View {
        ZStack {
            Circle().fill(dominantColor)
            ZStack {
                ForEach(Array(glowSlices.enumerated()), id: \.offset) { _, slice in
                    let fraction = slice.end - slice.start
                    RadialGradient(
                        colors: [
                            slice.color.opacity(slice.isMuted ? mutedGlowOpacity : glowOpacity),
                            .clear,
                        ],
                        center: glowCenter(forMidFraction: (slice.start + slice.end) / 2),
                        startRadius: 0,
                        endRadius: blobDiameter * (0.22 + 0.5 * fraction)
                    )
                }
            }
            .blur(radius: blobDiameter * 0.06)
        }
        .clipShape(.circle)
        .saturation(1.12)
        .overlay(sphereHighlight)
        .overlay(sphereShading)
        .overlay(glassRim)
    }

    private var orbShadow: some View {
        Circle()
            .fill(dominantColor.opacity(colorScheme == .dark ? 0.28 : 0.18))
            .frame(width: blobDiameter, height: blobDiameter)
            .blur(radius: diameter * 0.13)
            .offset(y: diameter * 0.04)
    }

    private var sphereHighlight: some View {
        RadialGradient(
            colors: [.white.opacity(colorScheme == .dark ? 0.26 : 0.42), .white.opacity(0)],
            center: UnitPoint(x: 0.34, y: 0.26),
            startRadius: 0,
            endRadius: blobDiameter * 0.6
        )
        .blendMode(.plusLighter)
        .clipShape(.circle)
    }

    private var sphereShading: some View {
        RadialGradient(
            colors: [.black.opacity(0), .black.opacity(colorScheme == .dark ? 0.28 : 0.14)],
            center: UnitPoint(x: 0.72, y: 0.82),
            startRadius: 0,
            endRadius: blobDiameter * 0.7
        )
        .blendMode(.multiply)
        .clipShape(.circle)
    }

    private var glassRim: some View {
        Circle().strokeBorder(
            LinearGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.22 : 0.4), .white.opacity(0)],
                startPoint: .top,
                endPoint: .center
            ),
            lineWidth: 1
        )
    }

    private var ring: some View {
        ZStack {
            ForEach(Array(ringSlices.enumerated()), id: \.offset) { _, slice in
                RingArc(start: slice.start, end: slice.end, inset: ringWidth / 2)
                    .stroke(
                        slice.color,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
            }
        }
    }

    private func glowCenter(forMidFraction fraction: Double) -> UnitPoint {
        let theta = fraction * 2 * .pi
        let radius = 0.33
        return UnitPoint(
            x: 0.5 + radius * sin(theta),
            y: 0.5 - radius * cos(theta)
        )
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private struct RingArc: Shape {
    var start: Double
    var end: Double
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - inset
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start * 360 - 90),
            endAngle: .degrees(end * 360 - 90),
            clockwise: false
        )
        return path
    }
}
