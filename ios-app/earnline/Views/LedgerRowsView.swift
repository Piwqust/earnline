import SwiftUI

/// Renders the heterogeneous ledger rows and owns their row-level interaction
/// wiring. `LedgerView` keeps screen orchestration and persistence; this view
/// keeps row presentation, swipe actions, and month-anchor reporting together.
struct LedgerRowsView: View {
    @Environment(AppModel.self) private var app

    let rows: [LedgerRow]
    let isSearching: Bool
    let activeComposerClientID: UUID?
    let composerMonth: Date?
    let onOpenClient: (UUID) -> Void
    let onToggleComposer: (Client, Date) -> Void
    let onSetStatus: (Entry, EntryStatus) -> Void
    let onEditEntry: (UUID) -> Void
    let onDeleteEntry: (UUID) -> Void
    let onEditHeading: (UUID) -> Void
    let onMoveHeading: (Heading, Int) -> Void
    let canMoveHeading: (Heading, Int) -> Bool
    let onDeleteHeading: (UUID) -> Void

    var body: some View {
        ForEach(rows) { row in
            rowView(row)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(insets(for: row))
        }
    }

    @ViewBuilder
    private func rowView(_ row: LedgerRow) -> some View {
        // A sync pull can invalidate a SwiftData model while a recycled List
        // row still exists. Skip that final render; the next query update
        // removes the row from the collection.
        if row.isInvalidated {
            EmptyView()
        } else {
            liveRowView(row)
        }
    }

    @ViewBuilder
    private func liveRowView(_ row: LedgerRow) -> some View {
        switch row {
        case .month(let month, let total):
            MonthDivider(title: DateFormat.month(month), total: total)
                .background(monthAnchorReader(month))
        case .heading(let heading):
            headingRow(heading)
                .background(monthAnchorReader(DateFormat.monthStart(of: heading.date)))
        case .client(let client, let month, let total):
            ClientChip(
                client: client,
                total: total,
                isComposing: !isSearching && activeComposerClientID == client.id,
                showsAdd: !isSearching,
                onOpen: { onOpenClient(client.id) },
                onAdd: { onToggleComposer(client, month) }
            )
            .background(monthAnchorReader(month))
        case .composer(let client):
            SmartComposer(client: client, month: composerMonth ?? .now)
                .transition(.opacity)
        case .entry(let entry):
            entryRow(entry)
                .background(monthAnchorReader(DateFormat.monthStart(of: entry.date)))
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        EntryRow(
            entry: entry,
            onSetStatus: { onSetStatus(entry, $0) },
            onEdit: { onEditEntry(entry.id) },
            onDelete: { onDeleteEntry(entry.id) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDeleteEntry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Theme.statusCanceled)

            Button {
                onEditEntry(entry.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(app.accentColor)
        }
    }

    private func headingRow(_ heading: Heading) -> some View {
        HStack(spacing: 8) {
            Text(heading.title.isEmpty ? String(localized: "Untitled") : heading.title)
                .appFont(15, .semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
        .contentShape(.rect)
        .onTapGesture { onEditHeading(heading.id) }
        .contextMenu {
            Button {
                onMoveHeading(heading, -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(!canMoveHeading(heading, -1))

            Button {
                onMoveHeading(heading, 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(!canMoveHeading(heading, 1))

            Divider()
            Button(role: .destructive) {
                onDeleteHeading(heading.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func monthAnchorReader(_ month: Date) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: MonthAnchorKey.self,
                value: [MonthAnchor(
                    month: month,
                    y: geometry.frame(in: .named("ledger")).minY
                )]
            )
        }
    }

    private func insets(for row: LedgerRow) -> EdgeInsets {
        switch row {
        case .month: EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16)
        case .heading: EdgeInsets(top: 12, leading: 16, bottom: 2, trailing: 16)
        case .client: EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
        case .composer: EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16)
        case .entry: EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        }
    }
}
