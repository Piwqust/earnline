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
            ForEach(EntryStatus.allCases) { s in
                Button { onSetStatus(s) } label: { Label(s.title, systemImage: s.symbol) }
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
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
