import Foundation
import SwiftData

/// Seeds the Figma scene on first launch so the app feels alive.
enum SampleData {
    private static let bundledLedgerImportVersion = 1
    private static let bundledLedgerImportKey = "bundledIncomeLedgerImportVersion"
    private static let legacyDemoCleanupVersion = 1
    private static let legacyDemoCleanupKey = "legacyDemoCleanupVersion"

    static func seedIfNeeded(_ context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<Client>())
        if existing?.isEmpty ?? true {
            importBundledLedgerIfNeeded(context)
        }
    }

    @discardableResult
    static func importBundledLedgerIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard defaults.integer(forKey: bundledLedgerImportKey) < bundledLedgerImportVersion else { return 0 }
        let inserted = IncomeLedgerImporter.importBundledLedger(into: context)
        defaults.set(bundledLedgerImportVersion, forKey: bundledLedgerImportKey)
        return inserted
    }

    @discardableResult
    static func cleanupLegacyDemoEntriesIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard defaults.integer(forKey: legacyDemoCleanupKey) < legacyDemoCleanupVersion else { return 0 }
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        var deleted = 0

        for entry in entries where isLegacyDemoEntry(entry) {
            SyncDeleteQueue.enqueue(.entry, id: entry.id, in: context)
            context.delete(entry)
            deleted += 1
        }

        defaults.set(legacyDemoCleanupVersion, forKey: legacyDemoCleanupKey)
        try? context.save()
        return deleted
    }

    static func seed(_ context: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        func day(_ d: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: d)) ?? now
        }
        func hold(_ d: Int, _ m: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: m, day: d)) ?? now
        }
        func monthsBack(_ n: Int, _ d: Int) -> Date {
            let base = cal.date(byAdding: .month, value: -n, to: now) ?? now
            let comps = cal.dateComponents([.year, .month], from: base)
            return cal.date(from: DateComponents(year: comps.year, month: comps.month, day: d)) ?? now
        }

        let mikita = Client(name: "Mikita", colorHex: "#0088FF", sortIndex: 0)
        let blackwave = Client(name: "BlackWave", colorHex: "#7B00FF", sortIndex: 1)
        context.insert(mikita)
        context.insert(blackwave)

        let mikitaEntries: [Entry] = [
            Entry(amount: 240, project: "LunaAI", task: "2 screens for my home page gggg yoyoyooy",
                  date: day(29), holdUntil: hold(25, min(month + 1, 12)), status: .inProgress, sortIndex: 0),
            Entry(amount: 300, project: "LunaAI", task: "Landing page",
                  date: day(26), status: .paid, sortIndex: 1),
            Entry(amount: 140, project: "LunaAI", task: "Logotype",
                  date: day(22), holdUntil: hold(14, min(month + 1, 12)), status: .inProgress, sortIndex: 2),
            Entry(amount: 875, project: "LunaAI", task: "Dashboard redesign",
                  date: day(18), status: .paid, sortIndex: 3),
            Entry(amount: 1000, project: "LunaAI", task: "Design system kickoff",
                  date: day(12), status: .logged, sortIndex: 4),
        ]
        let blackwaveEntries: [Entry] = [
            Entry(amount: 900, project: "BlackResell", task: "Admin Panel for him website",
                  date: day(20), status: .inProgress, sortIndex: 0),
            Entry(amount: 100, project: "BlackResell", task: "Telegram bot tweaks",
                  date: day(10), status: .paid, sortIndex: 1),
        ]

        // Previous months — so the ledger scrolls as one continuous list.
        let lastMonth: [(Client, Entry)] = [
            (mikita, Entry(amount: 480, project: "LunaAI", task: "Onboarding screens",
                           date: monthsBack(1, 24), status: .paid, sortIndex: 0)),
            (mikita, Entry(amount: 260, project: "LunaAI", task: "Icon set",
                           date: monthsBack(1, 15), status: .paid, sortIndex: 1)),
            (blackwave, Entry(amount: 700, project: "BlackResell", task: "Pricing page",
                              date: monthsBack(1, 9), status: .paid, sortIndex: 0)),
        ]
        let twoMonthsAgo: [(Client, Entry)] = [
            (mikita, Entry(amount: 540, project: "LunaAI", task: "Brand refresh",
                           date: monthsBack(2, 19), status: .paid, sortIndex: 0)),
            (blackwave, Entry(amount: 320, project: "BlackResell", task: "Landing hero",
                              date: monthsBack(2, 6), status: .paid, sortIndex: 0)),
        ]

        for e in mikitaEntries { e.client = mikita; context.insert(e) }
        for e in blackwaveEntries { e.client = blackwave; context.insert(e) }
        for (client, e) in lastMonth + twoMonthsAgo { e.client = client; context.insert(e) }

        try? context.save()
    }

    private static func isLegacyDemoEntry(_ entry: Entry) -> Bool {
        legacyDemoEntryKeys.contains(demoKey(client: entry.client?.name,
                                            project: entry.project,
                                            task: entry.task,
                                            amount: entry.amount,
                                            currencyCode: entry.currencyCode))
    }

    private static let legacyDemoEntryKeys: Set<String> = [
        demoKey(client: "Mikita", project: "LunaAI", task: "2 screens for my home page gggg yoyoyooy", amount: 240, currencyCode: "USD"),
        demoKey(client: "Mikita", project: "LunaAI", task: "Landing page", amount: 300, currencyCode: "USD"),
        demoKey(client: "Mikita", project: "LunaAI", task: "Logotype", amount: 140, currencyCode: "USD"),
        demoKey(client: "Mikita", project: "LunaAI", task: "Dashboard redesign", amount: 875, currencyCode: "USD"),
        demoKey(client: "Mikita", project: "LunaAI", task: "Design system kickoff", amount: 1000, currencyCode: "USD"),
        demoKey(client: "Mikita", project: "LunaAI", task: "Onboarding screens", amount: 480, currencyCode: "USD"),
        demoKey(client: "Mikita", project: "LunaAI", task: "Icon set", amount: 260, currencyCode: "USD"),
        demoKey(client: "Mikita", project: "LunaAI", task: "Brand refresh", amount: 540, currencyCode: "USD"),
        demoKey(client: "BlackWave", project: "BlackResell", task: "Admin Panel for him website", amount: 900, currencyCode: "USD"),
        demoKey(client: "BlackWave", project: "BlackResell", task: "Telegram bot tweaks", amount: 100, currencyCode: "USD"),
        demoKey(client: "BlackWave", project: "BlackResell", task: "Pricing page", amount: 700, currencyCode: "USD"),
        demoKey(client: "BlackWave", project: "BlackResell", task: "Landing hero", amount: 320, currencyCode: "USD"),
    ]

    private static func demoKey(client: String?,
                                project: String?,
                                task: String,
                                amount: Decimal,
                                currencyCode: String) -> String {
        let amountText = NSDecimalNumber(decimal: amount).stringValue
        return [
            client?.normalizedDemoKey ?? "",
            project?.normalizedDemoKey ?? "",
            task.normalizedDemoKey,
            amountText,
            currencyCode.uppercased(),
        ].joined(separator: "|")
    }
}

private extension String {
    var normalizedDemoKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
