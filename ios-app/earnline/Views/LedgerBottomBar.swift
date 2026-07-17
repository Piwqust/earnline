import SwiftUI

/// The ledger's bottom chrome, laid out the way Apple's own list screens do
/// it on iOS 26 (Notes, Mail): a leading "…" circle, the system search field
/// docked in the middle, and a trailing "+" circle. Everything is a native
/// bottom-bar toolbar item, so the system supplies the Liquid Glass surfaces,
/// the floating capsule grouping, and the search field's expand/collapse
/// choreography — no custom glass and no custom text field.
struct LedgerBottomBarItems: ToolbarContent {
    let clients: [Client]
    let pendingCount: Int
    let onInsights: () -> Void
    let onPending: () -> Void
    let onSettings: () -> Void
    let onIncome: (Client?) -> Void
    let onNewClient: () -> Void
    let onNewHeading: () -> Void
    let onPasteLines: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) { moreMenu }
        ToolbarSpacer(.fixed, placement: .bottomBar)
        // The `.searchable` field rests here, Mail-style, instead of
        // floating in its own detached bar.
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(.fixed, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) { addMenu }
    }

    private var addMenu: some View {
        Menu {
            if clients.isEmpty {
                Button { onIncome(nil) } label: {
                    MenuRowLabel("Income", glyph: "dollarsign")
                }
            } else {
                Menu {
                    ForEach(clients) { client in
                        Button { onIncome(client) } label: { Text(client.name) }
                    }
                } label: {
                    MenuRowLabel("Income", glyph: "dollarsign")
                }
            }
            Button(action: onNewClient) {
                MenuRowLabel("Client", glyph: "person.crop.circle.badge.plus")
            }
            Button(action: onNewHeading) {
                MenuRowLabel("Heading", glyph: "text.alignleft")
            }
            if !clients.isEmpty {
                Button(action: onPasteLines) {
                    MenuRowLabel("Paste lines", glyph: "doc.on.clipboard")
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .tint(.primary)
        .accessibilityLabel("Add")
        .accessibilityIdentifier("ledger.fab")
    }

    /// Search no longer needs a menu entry — the field itself rests in the
    /// toolbar, exactly like Notes and Mail.
    private var moreMenu: some View {
        Menu {
            Button(action: onInsights) {
                MenuRowLabel("Insights", glyph: "chart.bar")
            }
            Button(action: onPending) {
                MenuRowLabel(verbatim: pendingLabel, glyph: "clock")
            }
            Button(action: onSettings) {
                MenuRowLabel("Settings", glyph: "gearshape")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel("More")
        .accessibilityValue(pendingLabel)
        .accessibilityIdentifier("ledger.menu")
    }

    private var pendingLabel: String {
        pendingCount > 0
            ? String(localized: "Pending (\(pendingCount))")
            : String(localized: "Pending")
    }
}

/// Minimal filter chips floating just above the search field while a search
/// session is open: Date, Client, Project, Status. Each chip is a native
/// `Menu` of checkable rows backed by the same tokens the search field shows,
/// so a filter can be applied from the chip and removed from either place.
struct LedgerSearchFilterBar: View {
    let source: EntrySearch.FilterSource
    @Binding var tokens: [LedgerSearchToken]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                dateChip
                if !source.clients.isEmpty { clientChip }
                if !source.projects.isEmpty { projectChip }
                statusChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: Chips

    private var dateChip: some View {
        let selected = tokens.filter(\.isDateToken)
        return chip(title: "Date", systemImage: "calendar", selected: selected) {
            let years = source.years
            if years.count > 1 {
                // Sections per year, each openable as a whole ("All of…") or
                // month by month.
                ForEach(years, id: \.self) { year in
                    Section(String(year)) {
                        toggleRow(for: .year(year), titleOverride: String(localized: "All of \(String(year))"))
                        ForEach(source.months(in: year), id: \.self) { month in
                            toggleRow(for: .month(month), titleOverride: DateFormat.month(month))
                        }
                    }
                }
            } else {
                ForEach(source.months, id: \.self) { month in
                    toggleRow(for: .month(month))
                }
            }
        }
    }

    private var clientChip: some View {
        let selected = tokens.filter { if case .client = $0 { true } else { false } }
        return chip(title: "Client", systemImage: "person.crop.circle", selected: selected) {
            ForEach(source.clients, id: \.id) { client in
                toggleRow(for: .client(client.id, name: client.name))
            }
        }
    }

    private var projectChip: some View {
        let selected = tokens.filter { if case .project = $0 { true } else { false } }
        return chip(title: "Project", systemImage: "folder", selected: selected) {
            ForEach(source.projects, id: \.self) { project in
                toggleRow(for: .project(project))
            }
        }
    }

    private var statusChip: some View {
        let selected = tokens.filter { if case .status = $0 { true } else { false } }
        return chip(title: "Status", systemImage: "checkmark.circle", selected: selected) {
            ForEach(EntryStatus.allCases) { status in
                toggleRow(for: .status(status), systemImage: status.symbol)
            }
        }
    }

    // MARK: Pieces

    /// A resting chip names its filter; an active chip names the selection
    /// (or counts it) and switches to the prominent glass.
    @ViewBuilder
    private func chip(
        title: LocalizedStringKey,
        systemImage: String,
        selected: [LedgerSearchToken],
        @ViewBuilder rows: () -> some View
    ) -> some View {
        let menu = Menu(content: rows) {
            if let only = selected.first, selected.count == 1 {
                Label(only.label, systemImage: systemImage)
            } else if selected.count > 1 {
                Label {
                    Text("\(Text(title)) · \(selected.count)")
                } icon: {
                    Image(systemName: systemImage)
                }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .controlSize(.small)
        .accessibilityLabel(Text(title))

        if selected.isEmpty {
            menu.buttonStyle(.glass).tint(.primary)
        } else {
            menu.buttonStyle(.glassProminent)
        }
    }

    private func toggleRow(
        for token: LedgerSearchToken,
        titleOverride: String? = nil,
        systemImage: String? = nil
    ) -> some View {
        Toggle(isOn: binding(for: token)) {
            if let systemImage {
                Label(titleOverride ?? token.label, systemImage: systemImage)
            } else {
                Text(titleOverride ?? token.label)
            }
        }
    }

    private func binding(for token: LedgerSearchToken) -> Binding<Bool> {
        Binding(
            get: { tokens.contains(token) },
            set: { isOn in
                if isOn {
                    if !tokens.contains(token) { tokens.append(token) }
                } else {
                    tokens.removeAll { $0 == token }
                }
            }
        )
    }
}

private extension LedgerSearchToken {
    var isDateToken: Bool {
        switch self {
        case .month, .year: true
        case .client, .project, .status: false
        }
    }
}
