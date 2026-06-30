import SwiftUI

/// One income line. Tap to expand the task; tap the dot to change status.
struct EntryRow: View {
    @Environment(AppModel.self) private var app

    let entry: Entry
    var onSetStatus: (EntryStatus) -> Void = { _ in }
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var expanded = false

    private var baseAmount: Decimal {
        app.toBase(entry.amount, code: entry.currencyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label(0.45))
                    .padding(.top, 7)

                MoneyAmountText(baseAmount: baseAmount,
                                font: .lineAmount,
                                color: Theme.label,
                                minimumScaleFactor: 1,
                                isApproximate: !app.canConvert(entry.currencyCode))
                    .animation(.snappy(duration: 0.3), value: entry.amount)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

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
        .accessibilityActions {
            Button("Edit line") { onEdit() }
            ForEach(EntryStatus.allCases) { status in
                Button("Mark \(status.title)") { onSetStatus(status) }
            }
            Button("Delete", role: .destructive) { onDelete() }
        }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit line", systemImage: "pencil") }

            Section("Status") {
                ForEach(EntryStatus.allCases) { s in
                    Button { onSetStatus(s) } label: { Label(s.title, systemImage: s.symbol) }
                }
            }

            Section {
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
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
        if let hold = entry.holdUntil { parts.append("hold until \(DateFormat.dotted(hold))") }
        return parts.joined(separator: ", ")
    }

    private var description: Text {
        var result = AttributedString()
        if let project = entry.project, !project.isEmpty {
            var p = AttributedString(project); p.foregroundColor = Theme.label
            var sep = AttributedString(" : "); sep.foregroundColor = Theme.label(0.55)
            result = p + sep
        }
        var t = AttributedString(entry.task); t.foregroundColor = Theme.label
        result += t
        return Text(result)
    }

    private var statusMenu: some View {
        Menu {
            ForEach(EntryStatus.allCases) { s in
                Button { onSetStatus(s) } label: { Label(s.title, systemImage: s.symbol) }
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: entry.status.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entry.status.tint)
                .frame(width: 22, height: 22)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.3), value: entry.status)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var dateLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Theme.label(0.35))
            Text(DateFormat.dotted(entry.date))
                .foregroundStyle(Theme.label(0.7))
            if let hold = entry.holdUntil {
                Text("·").foregroundStyle(Theme.label(0.5))
                HStack(spacing: 3) {
                    Image(systemName: "calendar").font(.system(size: 10))
                    Text("hold until \(DateFormat.dotted(hold))")
                }
                .foregroundStyle(Theme.label(0.7))
                .lineLimit(1)
            }
        }
        .font(.caption)
    }
}

/// Rich preview shown under the press-and-hold context menu — a solid card so it
/// reads clearly against the dimmed background (the plain row is transparent).
private struct EntryContextPreview: View {
    @Environment(AppModel.self) private var app

    let entry: Entry

    private var baseAmount: Decimal {
        app.toBase(entry.amount, code: entry.currencyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: entry.status.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(entry.status.tint)
                MoneyAmountText(baseAmount: baseAmount,
                                font: .system(size: 22, weight: .semibold),
                                color: Theme.label,
                                isApproximate: !app.canConvert(entry.currencyCode))
                Spacer(minLength: 12)
                Text(entry.status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.status.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(entry.status.tint.opacity(0.14), in: .capsule)
            }

            if let project = entry.project, !project.isEmpty {
                Text(project)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label(0.55))
            }
            Text(entry.task)
                .font(.system(size: 17))
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label(0.45))
                Text(DateFormat.dotted(entry.date))
                    .foregroundStyle(Theme.label(0.7))
                if let hold = entry.holdUntil {
                    Text("· hold until \(DateFormat.dotted(hold))")
                        .foregroundStyle(Theme.label(0.5))
                }
            }
            .font(.system(size: 13))
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
            .font(.lineBody)
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
            .font(.lineBody)
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
