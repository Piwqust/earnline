import SwiftUI

/// Central design tokens lifted from the earn›line Figma. Light values are the
/// Figma originals; dark counterparts mirror the web client's dark tokens
/// (near-black desaturated surface, near-white ink). Dark mode is opt-in via
/// Settings, so every token must resolve per trait.
enum Theme {
    // MARK: Surfaces
    static let background = dynamic(light: "#F2F2F7", dark: "#0C0C0F")
    static let card = Color(uiColor: .tertiarySystemGroupedBackground)
    /// Solid card surface for sheet content — white on the gray sheet
    /// background (dark: elevated near-black), the ChatGPT grouped-card idiom.
    static let surface = dynamic(light: "#FFFFFF", dark: "#1C1C1E")

    // MARK: Labels
    static let label = dynamic(light: "#1A1A1A", dark: "#F2F2F4")
    /// UIKit semantic label colors for contexts that require a concrete `Color`
    /// (for example conditional styles and attributed strings). Prefer SwiftUI's
    /// `.secondary` and `.tertiary` hierarchical styles where type inference allows.
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
    static let quaternaryLabel = Color(uiColor: .quaternaryLabel)
    /// Reserved for continuous chart/decorative intensity. Text and controls
    /// use the semantic label tokens above so hierarchy adapts automatically.
    static func label(_ opacity: Double) -> Color { label.opacity(opacity) }

    static let hairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.10)
    })
    static let fillQuaternary = dynamic(light: "#74748014", dark: "#76768030")
    static let chipStroke = dynamic(light: "#EBEBEB", dark: "#2C2C2E")

    private static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }

    // MARK: Accents
    static let blue = Color(hex: "#0088FF")
    static let purple = Color(hex: "#7B00FF")
    static let green = Color(hex: "#16B364")

    /// User-selectable accent for interactive elements — ChatGPT's
    /// "Accent color" idiom. Blue is the default.
    enum Accent: String, CaseIterable, Identifiable {
        case blue, purple, green, orange, pink, teal

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .blue: Theme.blue
            case .purple: Theme.purple
            case .green: Theme.green
            case .orange: Color(hex: "#FF8A00")
            case .pink: Color(hex: "#E8467C")
            case .teal: Color(hex: "#0FB5BA")
            }
        }

        var title: String {
            switch self {
            case .blue: String(localized: "Blue")
            case .purple: String(localized: "Purple")
            case .green: String(localized: "Green")
            case .orange: String(localized: "Orange")
            case .pink: String(localized: "Pink")
            case .teal: String(localized: "Teal")
            }
        }

        /// Menu rows need original-color dots — SwiftUI tints menu icons to
        /// the accent, so route through UIKit's `.alwaysOriginal`.
        var dotImage: UIImage {
            let base = UIImage(systemName: "circle.fill") ?? UIImage()
            let sized = base.applyingSymbolConfiguration(.init(pointSize: 12)) ?? base
            return sized.withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
        }
    }

    /// Client swatch palette — the ten system accent tones from the Figma
    /// picker, laid out as two rows of five (green→purple, then blue→magenta).
    static let clientPalette: [String] = [
        "#34C759", // green
        "#FFCC00", // yellow
        "#FF8D28", // orange
        "#FF383C", // red
        "#CB30E0", // purple
        "#0088FF", // blue
        "#6155F5", // indigo
        "#FF2D55", // pink
        "#AC7F5E", // brown
        "#AB34C9", // magenta
    ]

    // MARK: Status
    static let statusPaid = Color(hex: "#8E8E93")      // gray — already paid, unremarkable
    static let statusProgress = Color(hex: "#FF8A00")  // orange — in progress
    static let statusCanceled = Color(hex: "#FF3B30")  // red — canceled

    // MARK: Metrics
    enum Radius {
        static let summary: CGFloat = 26
        /// Grouped sheet cards — the iOS 26 concentric radius (same as the
        /// summary pill), matching current ChatGPT's settings cards.
        static let card: CGFloat = 26
        static let chip: CGFloat = 100
        static let menu: CGFloat = 22
    }

    enum Space {
        static let screenH: CGFloat = 16
        static let section: CGFloat = 16
    }
}

extension View {
    /// A Figma-size font that scales with Dynamic Type. `Font.system(size:)`
    /// is frozen at its point size, so every text style routes through this
    /// instead; the scale factor is 1 at the default (Large) setting, keeping
    /// layouts pixel-identical to the Figma until the user opts into bigger
    /// text. Direct `.system(size:)` remains only on glyphs inside fixed-frame
    /// icon buttons, which deliberately don't grow.
    ///
    /// `relativeTo` picks the scaling curve: `.body` for running text,
    /// `.largeTitle` for display-size numbers (a 46 pt amount tripling at the
    /// largest accessibility size would dwarf the screen; the large-title
    /// curve grows it gently instead).
    func appFont(_ size: CGFloat,
                 _ weight: Font.Weight = .regular,
                 design: Font.Design = .default,
                 relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, style: style))
    }

    /// Grow a control's touch region to Apple's 44 pt minimum without changing
    /// what is drawn.
    ///
    /// Several chips in the app are deliberately compact — the Figma draws the
    /// composer's date and hold pills at 22 pt — but a compact *appearance* is
    /// not a licence for a compact *target*. `contentShape` after the frame is
    /// what makes the extra height tappable rather than merely reserved.
    ///
    /// Use this only where the surrounding row is already at least 44 pt tall,
    /// so nothing moves; otherwise the layout must change and that is a design
    /// decision, not a modifier.
    func hitTarget(minWidth: CGFloat = 44, minHeight: CGFloat = 44) -> some View {
        frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(.rect)
    }

    /// Grow only the touch region, by `inset` points on every side, leaving
    /// layout completely untouched.
    ///
    /// For controls whose drawn height the design fixes — the ledger's client
    /// chip and its "+ Line" button sit in a deliberately dense row — a real
    /// `frame(minHeight: 44)` would thicken the row, which is a design decision
    /// rather than a fix. A negatively-inset content shape reaches into the row's
    /// own padding instead: measured on the client row, the chip's reported target
    /// goes from 19 pt to 51 and "+ Line" from 18 pt to 42, with the drawn pills
    /// unchanged.
    ///
    /// It does not fully reach 44 pt, and cannot here: the client row allows 8 pt
    /// above and 4 pt below, so a 12 pt expansion already extends roughly 1 pt
    /// past where the next row's own inset begins. Closing the remaining gap
    /// means giving the row more height — ask the design, don't widen this.
    func expandedTapArea(_ inset: CGFloat = 12) -> some View {
        contentShape(.rect.inset(by: -inset))
    }
}

struct ScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let style: Font.TextStyle

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: typeSize.contentSizeCategory)
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle)
            .scaledValue(for: size, compatibleWith: traits)
        content.font(.system(size: scaled, weight: weight, design: design))
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
