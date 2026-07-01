import SwiftUI
import SwiftData

/// Full-text search across all income lines — client name, project, task, and
/// amount. Matching lives in `EntrySearch.matches` so it stays testable.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]

    @State private var query = ""

    private var results: [Entry] {
        guard !EntrySearch.normalized(query).isEmpty else { return [] }
        return entries.filter {
            $0.client != nil && EntrySearch.matches($0, query: query, clientName: $0.client?.name)
        }
    }

    private var sections: [(client: Client, entries: [Entry])] {
        Dictionary(grouping: results) { $0.client! }
            .map { (client: $0.key, entries: $0.value) }
            .sorted { $0.client.sortIndex < $1.client.sortIndex }
    }

    var body: some View {
        NavigationStack {
            List {
                if EntrySearch.normalized(query).isEmpty {
                    ContentUnavailableView(
                        "Search income",
                        systemImage: "magnifyingglass",
                        description: Text("Find lines by client, project, task, or amount.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(sections, id: \.client) { section in
                        Section(section.client.name) {
                            ForEach(section.entries) { entry in
                                NavigationLink(value: section.client) {
                                    SearchResultRow(entry: entry)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Client, project, task, or amount")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct SearchResultRow: View {
    let entry: Entry

    private var description: String {
        [entry.project, entry.task.isEmpty ? nil : entry.task]
            .compactMap { $0 }
            .joined(separator: " : ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(CurrencyFormatter.string(entry.amount, code: entry.currencyCode))
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(description.isEmpty ? "—" : description)
                    .lineLimit(1)
                    .foregroundStyle(Theme.label)
                Text(DateFormat.dotted(entry.date))
                    .font(.caption)
                    .foregroundStyle(Theme.label(0.5))
            }
            Spacer(minLength: 8)
            Image(systemName: entry.status.symbol)
                .font(.system(size: 13))
                .foregroundStyle(entry.status.tint)
        }
        .accessibilityElement(children: .combine)
    }
}
