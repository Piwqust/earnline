import Foundation
import SwiftData

/// Seeds the Figma scene on first launch so the app feels alive.
enum SampleData {
    private static let bundledLedgerImportVersion = 1
    private static let bundledLedgerImportKey = "bundledIncomeLedgerImportVersion"
    private static let legacyDemoCleanupVersion = 1
    private static let legacyDemoCleanupKey = "legacyDemoCleanupVersion"
    private static let leakedProductionFixtureCleanupVersion = 1
    private static let leakedProductionFixtureCleanupKey = "leakedProductionFixtureCleanupVersion"
    static let autoSeededDemoKey = "bundledLedgerAutoSeeded"

    static func seedIfNeeded(_ context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<Client>())
        if existing?.isEmpty ?? true {
            importBundledLedgerIfNeeded(context)
        }
    }

    @discardableResult
    static func importBundledLedgerIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard defaults.integer(forKey: bundledLedgerImportKey) < bundledLedgerImportVersion else { return 0 }
        let inserted = seedGenerated(context)
        defaults.set(bundledLedgerImportVersion, forKey: bundledLedgerImportKey)
        if inserted > 0 { defaults.set(true, forKey: autoSeededDemoKey) }
        return inserted
    }

    /// The bundled demo ledger only auto-seeds while sync is unconfigured. If
    /// the user then points the app at a real workspace, drop whatever demo
    /// rows never synced so sample data doesn't push into real data. Runs once,
    /// before the first configured sync. Demo rows the user already synced (or
    /// clients they hung real lines on) are left alone.
    @discardableResult
    static func purgeAutoSeededDemoIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) throws -> Int {
        guard defaults.bool(forKey: autoSeededDemoKey) else { return 0 }

        // Regenerate the demo ledger's deterministic IDs so we drop exactly the
        // rows we auto-seeded (and no real ones the user later added).
        let seed = generate()
        let demoEntryIDs = Set(seed.entries.map(\.id))
        let demoClientIDs = Set(seed.clients.map(\.id))

        var removed = 0
        let entries = try context.fetch(FetchDescriptor<Entry>())
        for entry in entries where demoEntryIDs.contains(entry.id) && entry.lastSyncedAt == nil {
            context.delete(entry)
            removed += 1
        }
        let clients = try context.fetch(FetchDescriptor<Client>())
        for client in clients where demoClientIDs.contains(client.id) && client.lastSyncedAt == nil {
            let hasRealEntries = client.entries.contains { !demoEntryIDs.contains($0.id) }
            if !hasRealEntries {
                context.delete(client)
                removed += 1
            }
        }
        if removed > 0 { try context.save() }
        // Mark this one-shot cleanup complete only after every deletion has
        // persisted. Otherwise a later sync could upload demo rows that a
        // failed cleanup merely appeared to remove.
        defaults.set(false, forKey: autoSeededDemoKey)
        return removed
    }

    @discardableResult
    static func cleanupLegacyDemoEntriesIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) throws -> Int {
        guard defaults.integer(forKey: legacyDemoCleanupKey) < legacyDemoCleanupVersion else { return 0 }
        let entries = try context.fetch(FetchDescriptor<Entry>())
        var deleted = 0

        // Fingerprint matching alone is too blunt: a real line that happens to
        // read "Acme Studio / Landing page / $300" would be swept up. Legacy
        // demo rows were seeded locally with random IDs and never pushed, so
        // restrict the purge to rows that have never synced — those also have
        // no remote counterpart, which makes a tombstone unnecessary.
        for entry in entries where entry.lastSyncedAt == nil && isLegacyDemoEntry(entry) {
            context.delete(entry)
            deleted += 1
        }

        try context.save()
        defaults.set(legacyDemoCleanupVersion, forKey: legacyDemoCleanupKey)
        return deleted
    }

    /// Older UI tests used the selected workspace's persistent store. Demo and
    /// stress fixtures could therefore survive the test process and appear in
    /// Production on the next normal launch. Remove only deterministic fixture
    /// IDs; preserve any real entry the user attached to a fixture client.
    @discardableResult
    static func cleanupLeakedProductionFixturesIfNeeded(
        _ context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> Int {
        guard defaults.integer(forKey: leakedProductionFixtureCleanupKey)
                < leakedProductionFixtureCleanupVersion else { return 0 }

        let demo = generate()
        let demoClientIDs = Set(demo.clients.map(\.id))
        let demoEntryIDs = Set(demo.entries.map(\.id))
        let stressClientIDs = Set((0..<8).map {
            DeterministicID.uuid("earnline-stress-client:\($0)")
        })
        let fixtureClientIDs = demoClientIDs.union(stressClientIDs)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        let protectedClientIDs = Set(entries.compactMap { entry -> UUID? in
            guard let ownerID = entry.client?.id, fixtureClientIDs.contains(ownerID) else { return nil }
            let isFixture = demoEntryIDs.contains(entry.id) || stressClientIDs.contains(ownerID)
            return isFixture ? nil : ownerID
        })

        var removed = 0
        for entry in entries {
            guard let ownerID = entry.client?.id else { continue }
            if demoEntryIDs.contains(entry.id) || stressClientIDs.contains(ownerID) {
                context.delete(entry)
                removed += 1
            }
        }

        let clients = try context.fetch(FetchDescriptor<Client>())
        for client in clients
        where fixtureClientIDs.contains(client.id) && !protectedClientIDs.contains(client.id) {
            context.delete(client)
            removed += 1
        }

        try context.save()
        defaults.set(leakedProductionFixtureCleanupVersion,
                     forKey: leakedProductionFixtureCleanupKey)
        return removed
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

    // MARK: - Generated demo ledger

    /// A year of demo income so the redesigned Insights land on a full, lively
    /// dataset. Deterministic so the auto-seed and the sync-purge agree on which
    /// rows are demo rows.
    struct SeedClient { let id: UUID; let name: String; let colorHex: String; let sortIndex: Int }
    struct SeedEntry {
        let id: UUID
        let clientID: UUID
        let amount: Decimal
        let currencyCode: String
        let project: String
        let task: String
        let date: Date
        let holdUntil: Date?
        let status: EntryStatus
        let sortIndex: Int
    }

    private static let seedClients: [SeedClient] = [
        ("Acme Studio", "#0088FF"), ("Northstar Labs", "#7B00FF"), ("River House", "#FF7A45"),
        ("Meridian Co", "#16B364"), ("Loop & Co", "#0FB5BA"),
    ].enumerated().map { index, client in
        SeedClient(id: DeterministicID.uuid("earnline-seed-client:\(client.0)"),
                   name: client.0, colorHex: client.1, sortIndex: index)
    }

    private static let seedProjects = [
        "Launch Kit", "Ops Console", "North Portal", "Brand System",
        "Mobile App", "Marketing Site", "Q3 Campaign",
    ]
    private static let seedTasks = [
        "Landing page", "Dashboard redesign", "Icon set", "Brand polish",
        "Onboarding screens", "Design review", "Prototype", "Illustration set",
        "Motion pass", "Component library", "Wireframes", "Style guide",
        "User testing", "Hero section", "Bug fixes",
    ]

    /// Deterministic pseudo-random in [0, 1) from a handful of integer keys, so
    /// the ledger regenerates identically for the auto-seed and the purge.
    private static func noise(_ keys: Int...) -> Double {
        var hash: UInt64 = 1469598103934665603
        for key in keys {
            var value = UInt64(bitPattern: Int64(key)) &+ 0x9e3779b97f4a7c15
            for _ in 0..<8 { hash = (hash ^ (value & 0xff)) &* 1099511628211; value >>= 8 }
        }
        return Double(hash % 1_000_000) / 1_000_000
    }

    private static func pick<T>(_ array: [T], _ fraction: Double) -> T {
        array[min(array.count - 1, Int(fraction * Double(array.count)))]
    }

    /// ~30 income lines a month across a rotating cast of clients, dates spread
    /// through each month, revenue trending up with month-to-month noise, mostly
    /// paid with a few in-progress lines and the odd hold and cancelation.
    static func generate(reference: Date = .now) -> (clients: [SeedClient], entries: [SeedEntry]) {
        let cal = Calendar.current
        let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: reference)) ?? reference
        let todayDay = cal.component(.day, from: reference)
        var entries: [SeedEntry] = []

        for offset in 0..<12 {
            guard let monthStart = cal.date(byAdding: .month, value: -offset, to: thisMonthStart) else { continue }
            let comps = cal.dateComponents([.year, .month], from: monthStart)
            guard let year = comps.year, let month = comps.month else { continue }
            let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30

            // 3–5 clients active this month, rotating so totals and the leaderboard shift.
            let activeCount = 3 + Int(noise(year, month, 7) * 3)
            let startIndex = Int(noise(year, month, 3) * Double(seedClients.count))
            let active = (0..<activeCount).map { seedClients[(startIndex + $0) % seedClients.count] }

            // Recent months earn more, with per-month noise for a lively trend.
            let trend = 0.6 + 0.4 * Double(12 - offset) / 12
            let scale = trend * (0.7 + 0.6 * noise(year, month, 11))
            let count = 26 + Int(noise(year, month, 5) * 9)

            for i in 0..<count {
                let day = min(daysInMonth, 1 + Int(noise(year, month, i, 1) * Double(daysInMonth)))
                if offset == 0 && day > todayDay { continue }
                guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { continue }

                let client = active[Int(noise(year, month, i, 2) * Double(active.count)) % active.count]
                let amount = Decimal(max(1, Int((((80 + noise(year, month, i, 4) * 820) * scale) / 10).rounded()) * 10))

                var status: EntryStatus = .paid
                var holdUntil: Date?
                let roll = noise(year, month, i, 12)
                if offset <= 2 && roll < 0.04 {
                    status = .canceled
                } else if offset == 0 && roll > 0.86 {
                    status = .inProgress
                    if roll > 0.93 {
                        holdUntil = cal.date(byAdding: .day, value: 14 + Int(noise(year, month, i, 13) * 20), to: date)
                    }
                } else if offset == 1 && roll > 0.93 {
                    status = .inProgress
                }

                entries.append(SeedEntry(
                    id: DeterministicID.uuid("earnline-seed-entry:\(year)-\(month)-\(i)"),
                    clientID: client.id,
                    amount: amount,
                    currencyCode: "USD",
                    project: pick(seedProjects, noise(year, month, i, 8)),
                    task: pick(seedTasks, noise(year, month, i, 9)),
                    date: date,
                    holdUntil: holdUntil,
                    status: status,
                    sortIndex: i))
            }
        }
        return (seedClients, entries)
    }

    /// Insert the generated demo ledger, skipping any rows already present
    /// (dedupe by deterministic id). Returns the number of clients + entries
    /// inserted, matching what `purgeAutoSeededDemoIfNeeded` will later remove.
    @discardableResult
    static func seedGenerated(_ context: ModelContext) -> Int {
        let seed = generate()
        let existingClients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        var clientsByID = Dictionary(existingClients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingEntryIDs = Set(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map(\.id))
        var inserted = 0

        for seedClient in seed.clients where clientsByID[seedClient.id] == nil {
            let client = Client(id: seedClient.id, name: seedClient.name, colorHex: seedClient.colorHex,
                                sortIndex: seedClient.sortIndex)
            context.insert(client)
            clientsByID[seedClient.id] = client
            inserted += 1
        }
        for seedEntry in seed.entries {
            guard !existingEntryIDs.contains(seedEntry.id), let client = clientsByID[seedEntry.clientID] else { continue }
            let entry = Entry(id: seedEntry.id, amount: seedEntry.amount, currencyCode: seedEntry.currencyCode,
                              project: seedEntry.project, task: seedEntry.task, date: seedEntry.date,
                              holdUntil: seedEntry.holdUntil, status: seedEntry.status, sortIndex: seedEntry.sortIndex,
                              createdAt: seedEntry.date, updatedAt: seedEntry.date)
            entry.client = client
            context.insert(entry)
            inserted += 1
        }
        try? context.save()
        return inserted
    }

    // MARK: - Stress dataset (developer tool)

    /// ~48 months × ~120 lines across 8 clients ≈ 5,800 entries — enough to
    /// make row-model and aggregation costs visible while profiling the
    /// ledger. Rows are inserted already `.synced` so the sync layer never
    /// pushes them to a workspace; "Reset and pull" clears them. Deterministic
    /// IDs make the button idempotent.
    @discardableResult
    static func seedStress(_ context: ModelContext) -> Int {
        let cal = Calendar.current
        let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now

        let palette = ["#0088FF", "#7B00FF", "#FF7A45", "#16B364", "#0FB5BA", "#FF3B30", "#8E8E93", "#FF8A00"]
        let stressClients = (0..<8).map { index in
            SeedClient(id: DeterministicID.uuid("earnline-stress-client:\(index)"),
                       name: "Stress Client \(index + 1)",
                       colorHex: palette[index % palette.count],
                       sortIndex: 100 + index)
        }

        let existingClients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        var clientsByID = Dictionary(existingClients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingEntryIDs = Set(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map(\.id))
        var inserted = 0

        for seedClient in stressClients where clientsByID[seedClient.id] == nil {
            let client = Client(id: seedClient.id, name: seedClient.name, colorHex: seedClient.colorHex,
                                sortIndex: seedClient.sortIndex, syncState: .synced, lastSyncedAt: .now)
            context.insert(client)
            clientsByID[seedClient.id] = client
            inserted += 1
        }

        for offset in 0..<48 {
            guard let monthStart = cal.date(byAdding: .month, value: -offset, to: thisMonthStart) else { continue }
            let comps = cal.dateComponents([.year, .month], from: monthStart)
            guard let year = comps.year, let month = comps.month else { continue }
            let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30

            let count = 110 + Int(noise(year, month, 21) * 20)
            for i in 0..<count {
                let id = DeterministicID.uuid("earnline-stress-entry:\(year)-\(month)-\(i)")
                guard !existingEntryIDs.contains(id) else { continue }
                let day = min(daysInMonth, 1 + Int(noise(year, month, i, 22) * Double(daysInMonth)))
                guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
                let client = clientsByID[stressClients[Int(noise(year, month, i, 23) * 8) % 8].id]
                let amount = Decimal(max(1, Int(noise(year, month, i, 24) * 90) * 10))
                let entry = Entry(id: id, amount: amount, currencyCode: "USD",
                                  project: pick(seedProjects, noise(year, month, i, 25)),
                                  task: pick(seedTasks, noise(year, month, i, 26)),
                                  date: date, status: .paid, sortIndex: i,
                                  createdAt: date, updatedAt: date,
                                  syncState: .synced, lastSyncedAt: date)
                entry.client = client
                context.insert(entry)
                inserted += 1
            }
        }
        try? context.save()
        return inserted
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
