import SwiftUI

/// Ledger navigation commands. Search remains the system `.searchable` field;
/// these two commands deliberately use the navigation bar rather than
/// `.bottomBar`. On iOS 26 a bottom-bar `Menu` combined with the system search
/// item causes SwiftUI to inject a `UIKitToolbar` into an unsupported hosting
/// hierarchy, which emits a runtime fault and can break after an OS update.
struct LedgerBottomBarItems: ToolbarContent {
    let clients: [Client]
    let pendingCount: Int
    let isSearching: Bool
    let filterSource: EntrySearch.FilterSource?
    @Binding var searchTokens: [LedgerSearchToken]
    let onInsights: () -> Void
    let onPending: () -> Void
    let onSettings: () -> Void
    let onIncome: (Client?) -> Void
    let onNewClient: () -> Void
    let onNewHeading: () -> Void
    let onPasteLines: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { leadingMenu }
        ToolbarItem(placement: .topBarTrailing) { addMenu }
    }

    @ViewBuilder
    private var leadingMenu: some View {
        if isSearching, let filterSource {
            LedgerSearchFiltersMenu(source: filterSource, tokens: $searchTokens)
        } else {
            moreMenu
        }
    }

    @ViewBuilder
    private var addMenu: some View {
        if clients.isEmpty {
            Button(action: onNewClient) {
                Label("Add client", systemImage: "person.crop.circle.badge.plus")
            }
            .tint(.primary)
            .accessibilityLabel("Add client")
            .accessibilityIdentifier("ledger.fab")
        } else {
            Menu {
                Menu {
                    ForEach(clients) { client in
                        Button { onIncome(client) } label: { Text(client.name) }
                    }
                } label: {
                    MenuRowLabel("Income", glyph: "dollarsign")
                }
                Button(action: onNewClient) {
                    MenuRowLabel("Client", glyph: "person.crop.circle.badge.plus")
                }
                Button(action: onNewHeading) {
                    MenuRowLabel("Event note", glyph: "note.text")
                }
                Button(action: onPasteLines) {
                    MenuRowLabel("Paste lines", glyph: "doc.on.clipboard")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .tint(.primary)
            .accessibilityLabel("Add")
            .accessibilityIdentifier("ledger.fab")
        }
    }

    /// Search uses the system `.searchable` field, so it does not need a
    /// duplicate menu entry.
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

/// One native menu in the bottom toolbar while a search is open. It keeps
/// every filter in the familiar system menu while the field remains focused
/// and continues to show the selected values as searchable tokens.
struct LedgerSearchFiltersMenu: View {
    let source: EntrySearch.FilterSource
    @Binding var tokens: [LedgerSearchToken]

    var body: some View {
        Menu {
            dateMenu
            if !source.clients.isEmpty { clientMenu }
            if !source.projects.isEmpty { projectMenu }
            statusMenu

            if !tokens.isEmpty {
                Divider()
                Button(role: .destructive) {
                    tokens.removeAll()
                } label: {
                    Label("Clear filters", systemImage: "xmark.circle")
                        .foregroundStyle(Theme.statusCanceled)
                }
                .tint(Theme.statusCanceled)
            }
        } label: {
            Label("Filters", systemImage: filterSymbol)
        }
        .tint(.primary)
        .accessibilityLabel("Filters")
        .accessibilityValue(filterAccessibilityValue)
        .accessibilityIdentifier("ledger.filters")
    }

    // MARK: Filter sections

    private var dateMenu: some View {
        Menu {
            let years = source.years
            if years.count > 1 {
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
        } label: {
            Label("Date", systemImage: "calendar")
        }
    }

    private var clientMenu: some View {
        Menu {
            ForEach(source.clients, id: \.id) { client in
                toggleRow(for: .client(client.id, name: client.name))
            }
        } label: {
            Label("Client", systemImage: "person.crop.circle")
        }
    }

    private var projectMenu: some View {
        Menu {
            ForEach(source.projects, id: \.self) { project in
                toggleRow(for: .project(project))
            }
        } label: {
            Label("Project", systemImage: "folder")
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(EntryStatus.allCases) { status in
                toggleRow(for: .status(status), systemImage: status.symbol)
            }
        } label: {
            Label("Status", systemImage: "checkmark.circle")
        }
    }

    private var filterSymbol: String {
        tokens.isEmpty
            ? "line.3.horizontal.decrease"
            : "line.3.horizontal.decrease.circle.fill"
    }

    private var filterAccessibilityValue: String {
        tokens.isEmpty ? String(localized: "No filters selected") : String(localized: "\(tokens.count) filters selected")
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
