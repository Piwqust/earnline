import SwiftUI

/// Central design tokens lifted from the earn›line Figma.
enum Theme {
    // MARK: Surfaces
    static let background = Color(hex: "#F2F2F7")
    static let card = Color(hex: "#1A1A1A").opacity(0.02)

    // MARK: Labels (vibrant primary, used with opacity steps)
    static let label = Color(hex: "#1A1A1A")
    static func label(_ opacity: Double) -> Color { label.opacity(opacity) }

    static let hairline = Color.black.opacity(0.10)
    static let fillQuaternary = Color(hex: "#74748014")
    static let chipStroke = Color(hex: "#EBEBEB")

    // MARK: Accents
    static let blue = Color(hex: "#0088FF")
    static let purple = Color(hex: "#7B00FF")

    /// Calm palette offered when creating new clients.
    static let clientPalette: [String] = [
        "#0088FF", // blue
        "#7B00FF", // purple
        "#FF7A45", // coral
        "#16B364", // green
        "#E8467C", // pink
        "#0FB5BA", // teal
        "#F5A623", // amber
        "#6E56CF", // indigo
    ]

    // MARK: Status
    static let statusPaid = Color(hex: "#8E8E93")      // gray — already paid, unremarkable
    static let statusProgress = Color(hex: "#FF8A00")  // orange — in progress
    static let statusCanceled = Color(hex: "#FF3B30")  // red — canceled

    // MARK: Metrics
    enum Radius {
        static let summary: CGFloat = 26
        static let card: CGFloat = 14
        static let chip: CGFloat = 100
        static let menu: CGFloat = 22
    }

    enum Space {
        static let screenH: CGFloat = 16
        static let section: CGFloat = 16
    }
}

extension Font {
    /// Large amount / line text — SF Pro Display Medium 20.
    static let lineAmount = Font.system(size: 20, weight: .medium)
    static let lineBody = Font.system(size: 20, weight: .medium)
    static let summaryTotal = Font.system(size: 20, weight: .medium)
    static let chipName = Font.system(size: 16, weight: .semibold)
    static let chipTotal = Font.system(size: 16, weight: .medium)
    static let caption = Font.system(size: 14, weight: .regular)
    static let labelMed = Font.system(size: 14, weight: .medium)
}
