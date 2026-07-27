import SwiftUI

/// The shared sheet vocabulary: a gray sheet with grouped cards at the large
/// concentric radius, sentence-case gray section labels, bare monochrome row
/// glyphs, hairlines inset to the text, the *system* sheet header (an inline
/// navigation title with `Button(role:)` toolbar buttons — Mail's compose
/// chrome), and a full-width glass-prominent pill as the single primary
/// action.
///
/// Every sheet and menu-like surface in the app composes these pieces so the
/// whole app speaks one dialect.

// MARK: - Title bar

extension View {
    /// The one canonical sheet header, built on Apple's ready-made template:
    /// a `NavigationStack` toolbar with `Button(role: .close)`. The system
    /// draws the whole thing — the circular Liquid Glass ✕ at the native
    /// glyph size/weight and primary-label color, the centered inline title,
    /// the localized accessibility label, and the scroll-edge fade under the
    /// bar — exactly the Mail-compose header, with nothing hand-tuned.
    /// Every close-only or bottom-CTA sheet (Insights, Settings, Pending,
    /// New client, Paste lines) applies this so their headers are
    /// pixel-identical; sheets that commit from the bar itself use
    /// `sheetEditorHeader` instead.
    func sheetHeader(_ title: LocalizedStringKey, onClose: @escaping () -> Void) -> some View {
        NavigationStack {
            self
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .toolbar {
                    // No explicit placement or size: the `.close` role carries
                    // its own system placement (top-trailing — the
                    // informational-sheet convention in App Store/Maps) and the
                    // full sheet-button size. `.tint(.primary)` opts the ✕
                    // glyph out of the app-wide accent: Apple never colors the
                    // close glyph, only the prominent action.
                    Button(role: .close, action: onClose)
                        .tint(.primary)
                }
        }
    }

    /// Editing-sheet header — Apple's ready-made compose bar (Mail's ✕/send):
    /// the same system role buttons as `sheetHeader`, so every header button
    /// in the app is drawn by the system at the identical circular sheet size.
    /// The `.close` ✕ discards edits from the leading slot; the `.confirm` ✓
    /// (the role's built-in checkmark glyph) commits from the trailing slot as
    /// the accent-prominent filled circle, dimmed while the form is invalid.
    /// The system owns size, glyph metrics, placement (mirrored in RTL),
    /// Dynamic Type, and localization; the ✓ picks up the app accent from the
    /// root-level `.tint`.
    func sheetEditorHeader(_ title: LocalizedStringKey,
                           saveEnabled: Bool = true,
                           onCancel: @escaping () -> Void,
                           onSave: @escaping () -> Void) -> some View {
        NavigationStack {
            self
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .toolbar {
                    // These are the same system role buttons as `sheetHeader`
                    // and render at the identical size — measured on iPhone 17:
                    // the ✕ glass disc is 132 px at the .large detent and 127 px
                    // at .medium (a ~4% uniform shrink iOS 26 applies to the whole
                    // partial-height sheet, chrome included — not to the button).
                    // `.controlSize` does NOT override it (verified no-op), and the
                    // only way to get the full size is to open at .large. So we
                    // leave the system defaults alone and don't compensate.
                    ToolbarItem(placement: .cancellationAction) {
                        // `.tint(.primary)` opts the ✕ glyph out of the accent,
                        // exactly as in `sheetHeader`.
                        Button(role: .close, action: onCancel)
                            .tint(.primary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm, action: onSave)
                            .disabled(!saveEnabled)
                            .accessibilityLabel(Text("Save"))
                    }
                }
        }
    }
}

extension View {
    /// The standard bottom action dock for a sheet — a full-width control (the
    /// `PillCTA`) floated over the background, mirroring `sheetHeader` at the
    /// other edge so every sheet's primary action sits in the same place.
    func sheetFooter<Footer: View>(@ViewBuilder _ footer: () -> Footer) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            footer()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                // No bottom padding: the button sits directly on top of the
                // home-indicator safe area — as low as the HIG allows.
                .background(Theme.background)
        }
    }

    /// The app's one save-failure dialog: an OK alert whose message is the
    /// failure reason. Bind it to the screen's `saveError` state so every
    /// surface reports persistence failures identically. The title varies only
    /// where the wording is more specific ("…save line", "…import lines").
    func saveErrorAlert(_ error: Binding<String?>,
                        title: LocalizedStringKey = "Could not save changes") -> some View {
        alert(title, isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? String(localized: "Try again."))
        }
    }
}

// MARK: - Cards

/// Solid rounded card (white on the gray sheet) that stacks rows, at the
/// iOS 26 concentric radius. Rows are separated explicitly with
/// `ChromeDivider` so insets stay under control.
struct ChromeCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

/// Sentence-case gray section label above a card — ChatGPT's "App" / "About"
/// settings headers, deliberately not the uppercase native style.
struct CardHeader: View {
    private let text: Text

    init(_ title: LocalizedStringKey) { text = Text(title) }
    init(verbatim: String) { text = Text(verbatim) }

    var body: some View {
        text
            .appFont(15, .medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 7)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Small gray print under a card.
struct CardFootnote<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .appFont(13)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.top, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

/// Standard card row: bare 17 pt monochrome glyph in a fixed column, then the
/// row's content. No tinted chips, no filled squares — the ChatGPT icon idiom.
struct ChromeRow<Content: View>: View {
    var icon: String?
    var alignTop = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: alignTop ? .top : .center, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 24)
                    .padding(.top, alignTop ? 15 : 0)
            }
            content
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

/// Hairline between card rows, inset to start under the text (past the icon
/// column) the way ChatGPT's settings hairlines align.
struct ChromeDivider: View {
    /// 52 = card padding (16) + icon column (24) + gap (12). Use 16 for rows
    /// without a leading glyph.
    var inset: CGFloat = 52

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - Client color picker

/// The client swatch grid shared by the New- and Edit-client sheets: the ten
/// `Theme.clientPalette` dots laid out in rows of five, justified edge to edge,
/// with the 2 pt white selection ring the Figma color card draws.
///
/// The ring appears on the dot that was picked; it does not travel there. Apple's
/// own color pickers (Reminders' list colors, Calendar's calendar colors) mark
/// the new selection in place, and `Animation` documents `.smooth`/`.snappy`/
/// `.bouncy` as the built-in springs — a hand-tuned
/// `spring(response:dampingFraction:)` driving a `matchedGeometryEffect` flight
/// across the grid was ours, not the system's.
struct ClientColorGrid: View {
    @Binding var selection: String
    /// Dots per row — the Figma lays the ten swatches out five and five.
    var perRow = 5

    private var rows: [[String]] {
        stride(from: 0, to: Theme.clientPalette.count, by: perRow).map { start in
            Array(Theme.clientPalette[start..<min(start + perRow, Theme.clientPalette.count)])
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element) { index, hex in
                        swatch(hex)
                        if index < row.count - 1 { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .padding(16)
        // One system spring for the whole grid: the ring fades out where it was
        // and in where it now belongs.
        .animation(.snappy, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func swatch(_ hex: String) -> some View {
        let selected = hex == selection
        // A real Button, not a tap gesture, so each swatch is a native control:
        // system press feedback, focus-engine reachability, and the button
        // accessibility trait come for free.
        return Button {
            selection = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay {
                    // The Figma "selection ring": a 2 pt white ring inset
                    // inside the dot (22 pt across the 30 pt swatch).
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .padding(4)
                        .opacity(selected ? 1 : 0)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Color"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Primary action

/// Full-width Liquid Glass prominent pill CTA in the user's accent color
/// (blue by default). Disabled renders as the washed gray pill.
struct PillCTA: View {
    @Environment(AppModel.self) private var app

    let title: LocalizedStringKey
    var isEnabled = true
    var action: () -> Void

    init(_ title: LocalizedStringKey, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        // The height and the label↔capsule padding are owned by the system's
        // `.large` control size — the same metrics as Apple's own full-width
        // prominent buttons. We only stretch the label to full width; we do NOT
        // force a `minHeight`, which would stack our padding on top of the glass
        // style's and make the pill look oversized for its text.
        Button(action: action) {
            Text(title)
                .appFont(17, .semibold)
                .foregroundStyle(isEnabled ? .white : Theme.tertiaryLabel)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(isEnabled ? app.accentColor : Theme.quaternaryLabel)
        .disabled(!isEnabled)
        .animation(.snappy(duration: 0.2), value: isEnabled)
    }
}
