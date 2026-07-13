import Foundation

/// Pure ledger projection: turns one cached aggregation snapshot into ordered
/// SwiftUI row models and search totals. Keeping this work outside the screen
/// makes the view responsible for presentation, not data-shaping loops.
@MainActor
struct LedgerRowBuilder {
    let clients: [Client]
    let headings: [Heading]
    let app: AppModel
    let composerRoute: LedgerComposerRoute?
    let searchQuery: String

    var activeComposerClient: Client? {
        guard let id = composerRoute?.clientID else { return nil }
        return clients.first { !$0.isInvalidated && $0.id == id }
    }

    var hasSearchQuery: Bool {
        !EntrySearch.normalized(searchQuery).isEmpty
    }

    var searchHits: [Entry] {
        guard hasSearchQuery else { return [] }
        return clients.flatMap { client -> [Entry] in
            guard !client.isInvalidated else { return [] }
            return client.entries.filter { entry in
                !entry.isInvalidated
                    && EntrySearch.matches(entry, query: searchQuery, clientName: client.name)
            }
        }
    }

    var searchEarnedTotal: Decimal {
        searchHits
            .filter { $0.status.isIncludedInEarnedTotals }
            .reduce(.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
    }

    func hasContent(in snapshot: Insights.LedgerSnapshot) -> Bool {
        !headings.isEmpty || snapshot.hasEntries
    }

    func blocks(in month: Date, snapshot: Insights.LedgerSnapshot) -> [LedgerBlock] {
        let headingBlocks = headings
            .filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .map(LedgerBlock.heading)
        let clientBlocks = sectionClients(in: month, snapshot: snapshot).map(LedgerBlock.client)
        return (headingBlocks + clientBlocks).sorted { $0.isOrderedBefore($1) }
    }

    func rows(
        in snapshot: Insights.LedgerSnapshot,
        isSearching: Bool,
        searchSnapshot: Insights.LedgerSnapshot?
    ) -> [LedgerRow] {
        if isSearching {
            return searchRows(in: searchSnapshot ?? snapshot)
        }

        var rows: [LedgerRow] = []
        for month in snapshot.months {
            let key = snapshot.key(for: month)
            rows.append(.month(month, snapshot.monthTotal(monthKey: key)))
            for block in blocks(in: month, snapshot: snapshot) {
                switch block {
                case .heading(let heading):
                    rows.append(.heading(heading))
                case .client(let client):
                    rows.append(.client(client, month, snapshot.total(of: client, monthKey: key)))
                    if isComposerMonth(month), activeComposerClient?.id == client.id {
                        rows.append(.composer(client))
                    }
                    rows.append(contentsOf: snapshot.entries(of: client, monthKey: key).map(LedgerRow.entry))
                }
            }
        }
        return rows
    }

    private func sectionClients(in month: Date, snapshot: Insights.LedgerSnapshot) -> [Client] {
        let key = snapshot.key(for: month)
        var result = clients.filter { !$0.isInvalidated && snapshot.hasEntries($0, monthKey: key) }
        if let composer = activeComposerClient,
           isComposerMonth(month),
           !result.contains(where: { $0.id == composer.id }) {
            result.append(composer)
        }
        return result
    }

    private func searchRows(in snapshot: Insights.LedgerSnapshot) -> [LedgerRow] {
        guard hasSearchQuery else { return [] }
        var rows: [LedgerRow] = []
        for month in snapshot.months {
            let key = snapshot.key(for: month)
            var monthRows: [LedgerRow] = []
            var monthTotal = Decimal.zero
            for block in blocks(in: month, snapshot: snapshot) {
                guard case .client(let client) = block, !client.isInvalidated else { continue }
                let matches = snapshot.entries(of: client, monthKey: key).filter { entry in
                    !entry.isInvalidated
                        && EntrySearch.matches(entry, query: searchQuery, clientName: client.name)
                }
                guard !matches.isEmpty else { continue }
                let earned = matches
                    .filter { $0.status.isIncludedInEarnedTotals }
                    .reduce(.zero) { $0 + app.toBase($1.amount, code: $1.currencyCode) }
                monthTotal += earned
                monthRows.append(.client(client, month, earned))
                monthRows.append(contentsOf: matches.map(LedgerRow.entry))
            }
            if !monthRows.isEmpty {
                rows.append(.month(month, monthTotal))
                rows.append(contentsOf: monthRows)
            }
        }
        return rows
    }

    private func isComposerMonth(_ month: Date) -> Bool {
        guard let composerMonth = composerRoute?.month else { return false }
        return Calendar.current.isDate(month, equalTo: composerMonth, toGranularity: .month)
    }
}
