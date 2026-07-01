import Foundation
import SwiftData

enum IncomeLedgerImporter {
    static let bundledLedger = """
    — Income for April from Acme Studio

    + $220 Landing page wireframes
    + $180 Brand polish
    + $99.50 QA fixes

    — Income for May from Northstar Labs

    + €320 Design review
    + $450 Dashboard prototype

    — Income for June from River House

    + 24k ₽ Event banners
    + 11k₽ Key visuals
    """

    struct ParsedEntry: Equatable {
        let id: UUID
        let clientName: String
        let amount: Decimal
        let currencyCode: String
        let project: String?
        let task: String
        let date: Date
        let sortIndex: Int
        let rawLine: String
    }

    @discardableResult
    static func importBundledLedger(into context: ModelContext, year: Int = Calendar.current.component(.year, from: .now)) throws -> Int {
        let parsed = parse(bundledLedger, year: year)
        guard !parsed.isEmpty else { return 0 }

        let existingClients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        var clientsByName = Dictionary(uniqueKeysWithValues: existingClients.map { ($0.name.normalizedLedgerKey, $0) })
        let existingEntries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let existingEntryIDs = Set(existingEntries.map(\.id))
        var inserted = 0

        for record in parsed {
            let clientKey = record.clientName.normalizedLedgerKey
            let client: Client
            if let existing = clientsByName[clientKey] {
                client = existing
            } else {
                let newClient = Client(id: clientID(record.clientName),
                                       name: record.clientName,
                                       colorHex: colorHex(for: clientsByName.count),
                                       sortIndex: clientsByName.count,
                                       createdAt: record.date,
                                       updatedAt: record.date)
                context.insert(newClient)
                clientsByName[clientKey] = newClient
                client = newClient
                inserted += 1
            }

            guard !existingEntryIDs.contains(record.id) else { continue }
            let entry = Entry(id: record.id,
                              amount: record.amount,
                              currencyCode: record.currencyCode,
                              project: record.project,
                              task: record.task,
                              date: record.date,
                              status: .paid,
                              sortIndex: record.sortIndex,
                              createdAt: record.date,
                              updatedAt: record.date)
            entry.client = client
            context.insert(entry)
            inserted += 1
        }

        try context.save()
        return inserted
    }

    static func parse(_ raw: String, year: Int) -> [ParsedEntry] {
        var currentMonth: Int?
        var currentClient: String?
        var sortIndexBySection: [String: Int] = [:]
        var results: [ParsedEntry] = []

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let section = parseSection(trimmed) {
                currentMonth = section.month
                currentClient = section.client
                continue
            }

            guard trimmed.hasPrefix("+"),
                  let month = currentMonth,
                  let client = currentClient else { continue }

            let sectionKey = "\(year)-\(month)-\(client.normalizedLedgerKey)"
            let sortIndex = sortIndexBySection[sectionKey, default: 0]
            sortIndexBySection[sectionKey] = sortIndex + 1

            let parsed = LineParser.parse(trimmed, defaultCurrency: "USD")
            guard let amount = parsed.amount else { continue }

            let date = date(year: year, month: month, day: min(28, sortIndex + 1))
            let task = parsed.task.isEmpty ? "Income" : parsed.task
            results.append(ParsedEntry(
                id: entryID(client: client, year: year, month: month, sortIndex: sortIndex, rawLine: trimmed),
                clientName: client,
                amount: amount,
                currencyCode: parsed.currencyCode,
                project: parsed.project,
                task: task,
                date: date,
                sortIndex: sortIndex,
                rawLine: trimmed
            ))
        }

        return results
    }

    private static func parseSection(_ line: String) -> (month: Int, client: String)? {
        let isIncomeHeading = line.localizedCaseInsensitiveContains("Доходы за")
            || line.localizedCaseInsensitiveContains("Income for")
        guard isIncomeHeading,
              let month = monthMap.first(where: { line.localizedCaseInsensitiveContains($0.key) })?.value,
              let range = line.range(of: " from ", options: [.caseInsensitive, .diacriticInsensitive])
                ?? line.range(of: " от ", options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let client = String(line[range.upperBound...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "—-")))
        return client.isEmpty ? nil : (month, client)
    }

    private static let monthMap: [String: Int] = [
        "январ": 1,
        "феврал": 2,
        "март": 3,
        "апрел": 4,
        "май": 5,
        "мая": 5,
        "июн": 6,
        "июл": 7,
        "август": 8,
        "сентябр": 9,
        "октябр": 10,
        "ноябр": 11,
        "декабр": 12,
        "january": 1,
        "february": 2,
        "march": 3,
        "april": 4,
        "may": 5,
        "june": 6,
        "july": 7,
        "august": 8,
        "september": 9,
        "october": 10,
        "november": 11,
        "december": 12,
    ]

    private static func clientID(_ name: String) -> UUID {
        DeterministicID.uuid("earnline-client:\(name.normalizedLedgerKey)")
    }

    private static func entryID(client: String, year: Int, month: Int, sortIndex: Int, rawLine: String) -> UUID {
        DeterministicID.uuid("earnline-entry:\(year)-\(month)-\(client.normalizedLedgerKey)-\(sortIndex)-\(rawLine)")
    }

    private static func colorHex(for index: Int) -> String {
        Theme.clientPalette[index % Theme.clientPalette.count]
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}

private extension String {
    var normalizedLedgerKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
