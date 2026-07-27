import SwiftUI

/// One income line. Tap to expand the task; tap the dot to change status.
struct EntryRow: View {
    @Environment(AppModel.self) private var app

    let entry: Entry
    var projectSymbol: ProjectSymbol?
    var onSetStatus: (EntryStatus) -> Void = { _ in }
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var expanded = false

    var body: some View {
        // A sync pull (remote tombstone, store reset) can delete this entry
        // while the row is still on screen; one more render before List drops
        // the row would trap in the model's getters (the crash log's
        // `Entry.amount.getter` assertion). Render nothing instead.
        if entry.isInvalidated {
            EmptyView()
        } else {
            rowBody
        }
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "plus")
                    .appFont(11, .semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 7)

                entryAmount

                if let projectSymbol {
                    Image(systemName: projectSymbol.systemImageName)
                        .appFont(14, .medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 24)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("entry.projectIcon")
                }

                EntryDescriptionText(text: description, expanded: expanded)

                statusMenu
            }

            dateLine
                .padding(.leading, 18)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.smooth(duration: 0.24)) { expanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("entry.row.\(entry.id.uuidString)")
        .accessibilityActions {
            Button("Edit line") { onEdit() }
            ForEach(EntryStatus.allCases) { status in
                Button("Mark \(status.title)") { onSetStatus(status) }
            }
            Button("Delete", role: .destructive) { onDelete() }
        }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit line", systemImage: "pencil") }
            statusPicker
            Section { deleteButton }
        } preview: {
            // Context-menu previews render in a detached hierarchy that does NOT
            // inherit the SwiftUI environment, so re-inject AppModel — the preview
            // (and its MoneyAmountText) reads it and would otherwise crash.
            EntryContextPreview(entry: entry)
                .environment(app)
        }
    }

    private var accessibilityDescription: String {
        var parts = [CurrencyFormatter.string(entry.amount, code: entry.currencyCode)]
        if let project = entry.project, !project.isEmpty { parts.append(project) }
        if !entry.task.isEmpty { parts.append(entry.task) }
        parts.append(entry.status.title)
        parts.append(DateFormat.dotted(entry.date))
        if let hold = entry.holdUntil { parts.append(String(localized: "hold until \(DateFormat.dotted(hold))")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var entryAmount: some View {
        if app.canConvert(entry.currencyCode) {
            MoneyAmountText(baseAmount: app.toBase(entry.amount, code: entry.currencyCode),
                            size: 20, weight: .medium,
                            color: Theme.label,
                            minimumScaleFactor: 1)
                .animation(.snappy(duration: 0.3), value: entry.amount)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        } else {
            Text(CurrencyFormatter.string(entry.amount, code: entry.currencyCode))
                .appFont(20, .medium)
                .foregroundStyle(Theme.statusProgress)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .accessibilityHint("Excluded from consolidated totals because no conversion rate is set")
        }
    }

    private var description: Text {
        var result = AttributedString()
        if let project = entry.project, !project.isEmpty {
            var p = AttributedString(project); p.foregroundColor = Theme.label
            var sep = AttributedString(" : "); sep.foregroundColor = Theme.secondaryLabel
            result = p + sep
        }
        var t = AttributedString(entry.task); t.foregroundColor = Theme.label
        result += t
        return Text(result)
    }

    private var statusMenu: some View {
        Menu {
            statusPicker
            Section { deleteButton }
        } label: {
            Image(systemName: entry.status.symbol)
                .appFont(14, .semibold)
                .foregroundStyle(entry.status.tint)
                .frame(minWidth: 22, minHeight: 22)
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.3), value: entry.status)
                // Grow the hit region to the HIG's 44 pt without moving the
                // 22 pt glyph: pad out to 44, take the shape, pull the layout
                // back in (hit testing isn't clipped to layout bounds).
                .padding(11)
                .contentShape(.circle)
                .padding(-11)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityIdentifier("entry.status")
    }

    /// Status choices as a native inline picker section — the system draws
    /// the leading selection checkmark (ChatGPT's model-picker idiom) inside
    /// the Liquid Glass menu, instead of hand-rolled checkmark labels.
    @ViewBuilder
    private var statusPicker: some View {
        Section("Status") {
            Picker("Status", selection: Binding(
                get: { entry.status },
                set: { onSetStatus($0) }
            )) {
                ForEach(EntryStatus.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.inline)
        }
    }

    /// Destructive action, isolated in its own trailing section so it reads as
    /// separate from the everyday status switches (ChatGPT's menu grouping).
    private var deleteButton: some View {
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
                .foregroundStyle(Theme.statusCanceled)
        }
        .tint(Theme.statusCanceled)
    }

    private var dateLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .appFont(9, .regular)
                .foregroundStyle(.tertiary)
            Text(DateFormat.dotted(entry.date))
                .foregroundStyle(.secondary)
            if let hold = entry.holdUntil {
                Text("·").foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    Image(systemName: "calendar").appFont(10)
                    Text("hold until \(DateFormat.dotted(hold))")
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .appFont(14)
    }
}

/// Rich preview shown under the press-and-hold context menu — a solid card so it
/// reads clearly against the dimmed background (the plain row is transparent).
private struct EntryContextPreview: View {
    @Environment(AppModel.self) private var app

    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: entry.status.symbol)
                    .appFont(16, .semibold)
                    .foregroundStyle(entry.status.tint)
                if app.canConvert(entry.currencyCode) {
                    MoneyAmountText(baseAmount: app.toBase(entry.amount, code: entry.currencyCode),
                                    size: 22, weight: .semibold,
                                    color: Theme.label)
                } else {
                    Text(CurrencyFormatter.string(entry.amount, code: entry.currencyCode))
                        .appFont(22, .semibold)
                        .foregroundStyle(Theme.statusProgress)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                Text(entry.status.title)
                    .appFont(13, .semibold)
                    .foregroundStyle(entry.status.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(entry.status.tint.opacity(0.14), in: .capsule)
            }

            if let project = entry.project, !project.isEmpty {
                Text(project)
                    .appFont(14, .semibold)
                    .foregroundStyle(.secondary)
            }
            Text(entry.task)
                .appFont(17)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .appFont(12)
                    .foregroundStyle(.tertiary)
                Text(DateFormat.dotted(entry.date))
                    .foregroundStyle(.secondary)
                if let hold = entry.holdUntil {
                    Text("· hold until \(DateFormat.dotted(hold))")
                        .foregroundStyle(.secondary)
                }
            }
            .appFont(13)
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

private struct EntryDescriptionText: View {
    let text: Text
    let expanded: Bool

    @State private var collapsedHeight: CGFloat = 24
    @State private var expandedHeight: CGFloat = 0

    private var targetHeight: CGFloat {
        let measured = expanded ? expandedHeight : collapsedHeight
        return max(measured, collapsedHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            displayText(lineLimit: nil)
                .opacity(expanded ? 1 : 0)
            displayText(lineLimit: 1)
                .opacity(expanded ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: targetHeight, alignment: .top)
        .clipped()
        .background(measurementViews)
        .animation(.smooth(duration: 0.24), value: expanded)
        .onPreferenceChange(EntryDescriptionHeightKey.self) { heights in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if let collapsed = heights[.collapsed] {
                    collapsedHeight = collapsed
                }
                if let expanded = heights[.expanded] {
                    expandedHeight = expanded
                }
            }
        }
    }

    private func displayText(lineLimit: Int?) -> some View {
        text
            .appFont(20, .medium)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var measurementViews: some View {
        ZStack(alignment: .topLeading) {
            measuredText(lineLimit: 1, mode: .collapsed)
            measuredText(lineLimit: nil, mode: .expanded)
        }
        .hidden()
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }

    private func measuredText(lineLimit: Int?, mode: EntryDescriptionHeightMode) -> some View {
        text
            .appFont(20, .medium)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: EntryDescriptionHeightKey.self,
                                           value: [mode: proxy.size.height])
                }
            )
    }
}

private enum EntryDescriptionHeightMode: Hashable {
    case collapsed
    case expanded
}

private struct EntryDescriptionHeightKey: PreferenceKey {
    static let defaultValue: [EntryDescriptionHeightMode: CGFloat] = [:]

    static func reduce(value: inout [EntryDescriptionHeightMode: CGFloat],
                       nextValue: () -> [EntryDescriptionHeightMode: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
