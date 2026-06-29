import SwiftUI

/// One income line. Tap to expand the task; tap the dot to change status.
struct EntryRow: View {
    let entry: Entry
    var onSetStatus: (EntryStatus) -> Void = { _ in }
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var expanded = false

    private var amountText: String {
        CurrencyFormatter.string(entry.amount, code: entry.currencyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label(0.45))

                Text(amountText)
                    .font(.lineAmount)
                    .foregroundStyle(Theme.label)
                    .monospacedDigit()
                    .layoutPriority(1)

                description
                    .font(.lineBody)
                    .lineLimit(expanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                statusMenu
            }

            dateLine
                .padding(.leading, 18)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.snappy(duration: 0.28)) { expanded.toggle() }
        }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit line", systemImage: "pencil") }

            Picker("Status", selection: Binding(get: { entry.status }, set: { onSetStatus($0) })) {
                ForEach(EntryStatus.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        } preview: {
            EntryContextPreview(entry: entry)
        }
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
    let entry: Entry

    private var amountText: String {
        CurrencyFormatter.string(entry.amount, code: entry.currencyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: entry.status.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(entry.status.tint)
                Text(amountText)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .monospacedDigit()
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

struct SwipeActionReveal<Content: View>: View {
    @Binding var isRevealed: Bool
    var onHide: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @GestureState private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 210
    private let openThreshold: CGFloat = 82

    private var revealOffset: CGFloat {
        let base = isRevealed ? actionWidth : 0
        return min(max(base - dragTranslation, 0), actionWidth)
    }

    private var revealProgress: CGFloat {
        actionWidth == 0 ? 0 : revealOffset / actionWidth
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if revealProgress > 0 {
                actionBar
                    .opacity(revealProgress)
                    .scaleEffect(0.96 + (0.04 * revealProgress), anchor: .trailing)
                    .allowsHitTesting(isRevealed)
                    .accessibilityHidden(!isRevealed)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: -revealOffset)
                .overlay {
                    if isRevealed {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { close() }
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .clipped()
        .gesture(horizontalDrag)
        .animation(.snappy(duration: 0.26), value: isRevealed)
        .animation(.snappy(duration: 0.18), value: dragTranslation)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            SwipeActionButton(
                title: "Hide",
                systemName: "eye.slash",
                color: Theme.actionHide,
                action: performHide
            )
            SwipeActionButton(
                title: "Edit",
                systemName: "pencil",
                color: Theme.blue,
                action: performEdit
            )
            SwipeActionButton(
                title: "Delete",
                systemName: "trash",
                color: Theme.actionDelete,
                action: performDelete
            )
        }
        .frame(width: actionWidth, alignment: .trailing)
    }

    private var horizontalDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base = isRevealed ? actionWidth : 0
                let projectedOffset = min(max(base - value.predictedEndTranslation.width, 0), actionWidth)
                withAnimation(.snappy(duration: 0.28)) {
                    isRevealed = projectedOffset > openThreshold
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.24)) { isRevealed = false }
    }

    private func performHide() {
        onHide()
    }

    private func performEdit() {
        onEdit()
    }

    private func performDelete() {
        onDelete()
    }
}

private struct SwipeActionButton: View {
    let title: String
    let systemName: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 38)
                    .background(color, in: .capsule)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 60)
            }
            .frame(width: 60, height: 68, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
