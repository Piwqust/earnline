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
        do {
            let inserted = try IncomeLedgerImporter.importBundledLedger(into: context)
            defaults.set(bundledLedgerImportVersion, forKey: bundledLedgerImportKey)
            return inserted
        } catch {
            return 0
        }
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
        do {
            try context.save()
            return deleted
        } catch {
            return 0
        }
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

        let acme = Client(name: "Acme Studio", colorHex: "#0088FF", sortIndex: 0)
        let northstar = Client(name: "Northstar Labs", colorHex: "#7B00FF", sortIndex: 1)
        context.insert(acme)
        context.insert(northstar)

        let acmeEntries: [Entry] = [
            Entry(amount: 240, project: "Launch Kit", task: "Two homepage screens",
                  date: day(29), holdUntil: hold(25, min(month + 1, 12)), status: .inProgress, sortIndex: 0),
            Entry(amount: 300, project: "Launch Kit", task: "Landing page",
                  date: day(26), status: .paid, sortIndex: 1),
            Entry(amount: 140, project: "Launch Kit", task: "Logotype",
                  date: day(22), holdUntil: hold(14, min(month + 1, 12)), status: .inProgress, sortIndex: 2),
            Entry(amount: 875, project: "Ops Console", task: "Dashboard redesign",
                  date: day(18), status: .paid, sortIndex: 3),
            Entry(amount: 1000, project: "Ops Console", task: "Canceled scope",
                  date: day(12), status: .canceled, sortIndex: 4),
        ]
        let northstarEntries: [Entry] = [
            Entry(amount: 900, project: "North Portal", task: "Admin panel",
                  date: day(20), status: .inProgress, sortIndex: 0),
            Entry(amount: 100, project: "North Portal", task: "Integration tweaks",
                  date: day(10), status: .paid, sortIndex: 1),
        ]

        // Previous months — so the ledger scrolls as one continuous list.
        let lastMonth: [(Client, Entry)] = [
            (acme, Entry(amount: 480, project: "Launch Kit", task: "Onboarding screens",
                           date: monthsBack(1, 24), status: .paid, sortIndex: 0)),
            (acme, Entry(amount: 260, project: "Launch Kit", task: "Icon set",
                           date: monthsBack(1, 15), status: .paid, sortIndex: 1)),
            (northstar, Entry(amount: 700, project: "North Portal", task: "Pricing page",
                              date: monthsBack(1, 9), status: .paid, sortIndex: 0)),
        ]
        let twoMonthsAgo: [(Client, Entry)] = [
            (acme, Entry(amount: 540, project: "Launch Kit", task: "Brand refresh",
                           date: monthsBack(2, 19), status: .paid, sortIndex: 0)),
            (northstar, Entry(amount: 320, project: "North Portal", task: "Landing hero",
                              date: monthsBack(2, 6), status: .paid, sortIndex: 0)),
        ]

        for e in acmeEntries { e.client = acme; context.insert(e) }
        for e in northstarEntries { e.client = northstar; context.insert(e) }
        for (client, e) in lastMonth + twoMonthsAgo { e.client = client; context.insert(e) }

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save sample data: \(error.localizedDescription)")
        }
    }

    private static func isLegacyDemoEntry(_ entry: Entry) -> Bool {
        legacyDemoEntryKeys.contains(demoKey(client: entry.client?.name,
                                            project: entry.project,
                                            task: entry.task,
                                            amount: entry.amount,
                                            currencyCode: entry.currencyCode))
    }

    private static let legacyDemoEntryKeys: Set<String> = [
        demoKey(client: "Acme Studio", project: "Launch Kit", task: "Two homepage screens", amount: 240, currencyCode: "USD"),
        demoKey(client: "Acme Studio", project: "Launch Kit", task: "Landing page", amount: 300, currencyCode: "USD"),
        demoKey(client: "Acme Studio", project: "Launch Kit", task: "Logotype", amount: 140, currencyCode: "USD"),
        demoKey(client: "Acme Studio", project: "Ops Console", task: "Dashboard redesign", amount: 875, currencyCode: "USD"),
        demoKey(client: "Acme Studio", project: "Ops Console", task: "Canceled scope", amount: 1000, currencyCode: "USD"),
        demoKey(client: "Acme Studio", project: "Launch Kit", task: "Onboarding screens", amount: 480, currencyCode: "USD"),
        demoKey(client: "Acme Studio", project: "Launch Kit", task: "Icon set", amount: 260, currencyCode: "USD"),
        demoKey(client: "Acme Studio", project: "Launch Kit", task: "Brand refresh", amount: 540, currencyCode: "USD"),
        demoKey(client: "Northstar Labs", project: "North Portal", task: "Admin panel", amount: 900, currencyCode: "USD"),
        demoKey(client: "Northstar Labs", project: "North Portal", task: "Integration tweaks", amount: 100, currencyCode: "USD"),
        demoKey(client: "Northstar Labs", project: "North Portal", task: "Pricing page", amount: 700, currencyCode: "USD"),
        demoKey(client: "Northstar Labs", project: "North Portal", task: "Landing hero", amount: 320, currencyCode: "USD"),
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
