import SwiftUI

/// A row inside a system `Menu`: a title beside a monochrome glyph.
///
/// System menus tint their item glyphs to the app-wide accent (blue by
/// default), which the app deliberately reserves for status and totals. To keep
/// the menu list neutral, the SF Symbol is pre-rendered in the primary label
/// color through a `.alwaysOriginal` `UIImage` — the one reliable way to opt a
/// menu glyph out of that tint (SwiftUI's `.foregroundStyle`/`.tint` inside menu
/// content is ignored by the system menu renderer). `.label` is used so the
/// glyph stays legible against the menu material in both light and dark mode.
struct MenuRowLabel: View {
    private let title: Text
    private let glyph: String

    init(_ title: LocalizedStringKey, glyph: String) {
        self.title = Text(title)
        self.glyph = glyph
    }

    init(verbatim title: String, glyph: String) {
        self.title = Text(verbatim: title)
        self.glyph = glyph
    }

    var body: some View {
        Label { title } icon: { Image(uiImage: Self.monochromeGlyph(glyph)) }
    }

    private static func monochromeGlyph(_ systemName: String) -> UIImage {
        let base = UIImage(systemName: systemName) ?? UIImage()
        return base.withTintColor(.label, renderingMode: .alwaysOriginal)
    }
}

/// The compact circular Liquid-Glass "+" used on client chips.
struct GlassCircleButton: View {
    var systemName: String = "plus"
    var size: CGFloat = 15
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.label)
                .frame(width: 28, height: 28)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }
}
