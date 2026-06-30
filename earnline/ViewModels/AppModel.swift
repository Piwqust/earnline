import SwiftUI
import Observation
import SwiftData
import Supabase

/// App-wide UI state + currency settings (persisted in UserDefaults).
@MainActor
@Observable
final class AppModel {
    nonisolated static let supportedCurrencyCodes = ["USD", "EUR", "GBP", "RUB", "UAH"]
    nonisolated static let defaultBaseCurrencyCode = "USD"
    nonisolated static let defaultSecondaryCurrencyCode = "RUB"
    nonisolated static let defaultExchangeRate = 98.0

    var baseCurrencyCode: String {
        didSet {
            let normalized = Self.normalizedCurrencyCode(baseCurrencyCode, fallback: oldValue)
            if baseCurrencyCode != normalized {
                baseCurrencyCode = normalized
                return
            }
            if secondaryCurrencyCode == baseCurrencyCode {
                secondaryCurrencyCode = Self.replacementCurrencyCode(excluding: baseCurrencyCode)
            }
            defaults.set(baseCurrencyCode, forKey: "baseCurrencyCode")
        }
    }
    var secondaryCurrencyCode: String {
        didSet {
            let normalized = Self.normalizedCurrencyCode(secondaryCurrencyCode, fallback: oldValue)
            if secondaryCurrencyCode != normalized {
                secondaryCurrencyCode = normalized
                return
            }
            if secondaryCurrencyCode == baseCurrencyCode {
                secondaryCurrencyCode = Self.replacementCurrencyCode(excluding: baseCurrencyCode)
                return
            }
            defaults.set(secondaryCurrencyCode, forKey: "secondaryCurrencyCode")
        }
    }
    /// Secondary units per 1 base unit (e.g. RUB per USD).
    var rate: Double {
        didSet {
            let normalized = Self.validExchangeRate(rate, fallback: oldValue)
            if rate != normalized {
                rate = normalized
                return
            }
            defaults.set(rate, forKey: "rate")
        }
    }
    var supabaseURLString: String {
        didSet {
            defaults.set(supabaseURLString, forKey: "supabaseURLString")
            resetSupabaseClient()
        }
    }
    var supabaseKey: String {
        didSet {
            defaults.set(supabaseKey, forKey: "supabaseKey")
            resetSupabaseClient()
        }
    }
    var workspaceID: String {
        didSet {
            let trimmed = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
            if workspaceID != trimmed {
                workspaceID = trimmed
                return
            }
            defaults.set(workspaceID, forKey: "workspaceID")
            if realtimeContext != nil { restartRealtime() }
        }
    }
    var isSyncing = false
    var syncMessage = "Offline"
    var syncError: String?
    var lastSyncAt: Date? {
        didSet { defaults.set(lastSyncAt, forKey: "lastSyncAt") }
    }

    /// The month currently under the top of the scroll — shown in the summary pill.
    var displayedMonth: Date = DateFormat.monthStart(of: .now)

    private let defaults = UserDefaults.standard
    @ObservationIgnored private var supabaseClient: SupabaseClient?
    @ObservationIgnored private var queuedSyncTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeChannel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeContext: ModelContext?

    init() {
        let resolvedBaseCurrencyCode = Self.normalizedCurrencyCode(defaults.string(forKey: "baseCurrencyCode"),
                                                                   fallback: Self.defaultBaseCurrencyCode)
        baseCurrencyCode = resolvedBaseCurrencyCode
        let savedSecondary = Self.normalizedCurrencyCode(defaults.string(forKey: "secondaryCurrencyCode"),
                                                         fallback: Self.defaultSecondaryCurrencyCode)
        secondaryCurrencyCode = savedSecondary == resolvedBaseCurrencyCode
            ? Self.replacementCurrencyCode(excluding: resolvedBaseCurrencyCode)
            : savedSecondary
        let r = defaults.double(forKey: "rate")
        rate = Self.validExchangeRate(r, fallback: Self.defaultExchangeRate)
        supabaseURLString = defaults.string(forKey: "supabaseURLString") ?? SupabaseProjectDefaults.url
        supabaseKey = defaults.string(forKey: "supabaseKey") ?? SupabaseProjectDefaults.publishableKey
        workspaceID = defaults.string(forKey: "workspaceID") ?? SupabaseProjectDefaults.workspaceID
        lastSyncAt = defaults.object(forKey: "lastSyncAt") as? Date
        syncMessage = isSupabaseConfigured ? "Ready" : "Offline"
    }

    // MARK: Currency

    /// Base-currency value of one unit of `code`, or `nil` when the app has no
    /// rate for it (anything other than the base or secondary currency).
    func conversionRate(from code: String) -> Decimal? {
        if code == baseCurrencyCode { return 1 }
        if code == secondaryCurrencyCode { return 1 / rateDecimal }
        return nil
    }

    /// Whether an amount in `code` can be converted to the base currency.
    /// Anything else is summed 1:1 as a lossy fallback and flagged in the UI.
    func canConvert(_ code: String) -> Bool { conversionRate(from: code) != nil }

    /// Convert an entry amount into the base currency.
    func toBase(_ amount: Decimal, code: String) -> Decimal {
        if code == baseCurrencyCode { return amount }
        if code == secondaryCurrencyCode { return amount / rateDecimal }
        // No rate for this currency (e.g. a EUR line while base/secondary are
        // USD/RUB). This is a legitimate runtime state — a synced or imported
        // row in a third currency — not a programmer error, so we don't trap.
        // The 1:1 result is lossy; `canConvert` lets the UI mark it and Settings
        // count it so it's visible rather than silently wrong.
        #if DEBUG
        print("⚠️ toBase: no rate for \(code); summing 1:1 (flagged via canConvert).")
        #endif
        return amount
    }

    /// The secondary-currency value for a base amount.
    func secondary(_ base: Decimal) -> Decimal { base * rateDecimal }

    func primaryString(_ base: Decimal) -> String {
        CurrencyFormatter.string(base, code: baseCurrencyCode)
    }
    func secondaryString(_ base: Decimal) -> String {
        CurrencyFormatter.string(secondary(base), code: secondaryCurrencyCode)
    }

    // MARK: Grouping & totals

    func entries(of client: Client, in month: Date) -> [Entry] {
        client.entries
            .filter { sameMonth($0.date, month) }
            .sorted { $0.sortIndex == $1.sortIndex ? $0.createdAt > $1.createdAt : $0.sortIndex < $1.sortIndex }
    }

    func earnedEntries(of client: Client, in month: Date) -> [Entry] {
        entries(of: client, in: month).filter { $0.status.isIncludedInEarnedTotals }
    }

    func total(of client: Client, in month: Date) -> Decimal {
        earnedEntries(of: client, in: month).reduce(Decimal.zero) { $0 + toBase($1.amount, code: $1.currencyCode) }
    }

    func clientsWithEntries(_ clients: [Client], in month: Date) -> [Client] {
        clients
            .filter { !entries(of: $0, in: month).isEmpty }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func monthTotal(_ clients: [Client], in month: Date) -> Decimal {
        clients.reduce(Decimal.zero) { $0 + total(of: $1, in: month) }
    }

    // MARK: Insights

    /// Earned base-currency total for each of the last `lastNMonths` months,
    /// oldest first. Months with no data come back as 0 so the chart is continuous.
    func monthlySeries(_ clients: [Client], lastNMonths: Int = 12) -> [(month: Date, total: Decimal)] {
        let calendar = Calendar.current
        let thisMonth = DateFormat.monthStart(of: .now)
        return (0..<max(lastNMonths, 1)).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return (month: month, total: monthTotal(clients, in: month))
        }
    }

    /// Clients ranked by earned base-currency total over the last `lastNMonths`
    /// months, highest first, dropping clients with nothing earned.
    func topClients(_ clients: [Client], lastNMonths: Int = 12, limit: Int = 3) -> [(client: Client, total: Decimal)] {
        let months = monthlySeries(clients, lastNMonths: lastNMonths).map(\.month)
        return clients
            .map { client in
                (client: client, total: months.reduce(Decimal.zero) { $0 + total(of: client, in: $1) })
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Pending / outstanding

    /// All in-progress lines, soonest `holdUntil` first (undated last), then by
    /// creation. These are the lines that still need follow-up.
    func pendingEntries(_ clients: [Client]) -> [Entry] {
        clients
            .flatMap(\.entries)
            .filter { $0.status == .inProgress }
            .sorted { a, b in
                switch (a.holdUntil, b.holdUntil) {
                case let (l?, r?): return l == r ? a.createdAt < b.createdAt : l < r
                case (_?, nil): return true   // dated before undated
                case (nil, _?): return false
                case (nil, nil): return a.createdAt < b.createdAt
                }
            }
    }

    /// An in-progress line whose hold date is already in the past.
    func isOverdue(_ entry: Entry) -> Bool {
        guard entry.status == .inProgress, let hold = entry.holdUntil else { return false }
        return hold < Calendar.current.startOfDay(for: .now)
    }

    /// Rebuild local hold-until reminders from the current entries. Called after
    /// every save point (via `queueSync`) and after a sync pull, so the schedule
    /// always matches the data without any delta tracking.
    func refreshPendingReminders(context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        PendingNotifications.sync(entries)
    }

    /// Months containing at least one visible entry (newest first), always including this month.
    func monthsWithData(_ clients: [Client]) -> [Date] {
        var set = Set<Date>()
        for c in clients {
            for e in c.entries {
                set.insert(DateFormat.monthStart(of: e.date))
            }
        }
        set.insert(DateFormat.monthStart(of: .now))
        return set.sorted(by: >)
    }

    private func sameMonth(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, equalTo: b, toGranularity: .month)
    }

    // MARK: Supabase

    var isSupabaseConfigured: Bool {
        URL(string: supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            && !supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshSupabaseSession() async {
        guard isSupabaseConfigured else {
            syncMessage = "Offline"
            return
        }
        do {
            _ = try supabase()
            syncMessage = "Ready"
            syncError = nil
        } catch {
            syncMessage = "Needs setup"
            syncError = error.localizedDescription
        }
    }

    func syncNow(context: ModelContext) async {
        guard isSupabaseConfigured else {
            syncMessage = "Offline"
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        syncMessage = "Syncing..."
        syncError = nil
        do {
            let completedAt = try await SyncCoordinator.sync(context: context,
                                                             client: supabase(),
                                                             workspaceID: workspaceID,
                                                             lastPulledAt: lastSyncAt)
            lastSyncAt = completedAt
            syncMessage = "Synced"
            try context.save()
            refreshPendingReminders(context: context)
        } catch {
            syncMessage = "Needs sync"
            syncError = error.localizedDescription
        }
        isSyncing = false
    }

    func queueSync(context: ModelContext) {
        refreshPendingReminders(context: context)
        queuedSyncTask?.cancel()
        queuedSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.syncNow(context: context)
        }
    }

    private func supabase() throws -> SupabaseClient {
        if let supabaseClient { return supabaseClient }
        let urlText = supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText), !key.isEmpty else {
            throw SyncError.missingConfiguration
        }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        supabaseClient = client
        return client
    }

    private func resetSupabaseClient() {
        supabaseClient = nil
        syncMessage = isSupabaseConfigured ? "Ready" : "Offline"
        // Config (URL/key/workspace) changed — rebuild the realtime subscription
        // against the new client/filter if we were already listening.
        if realtimeContext != nil {
            restartRealtime()
        }
    }

    // MARK: Realtime

    /// Subscribe to workspace changes and trigger a debounced sync on any remote
    /// insert/update/delete. One schema-wide channel filtered by `workspace_id`
    /// covers clients, entries, headings, and tombstones.
    func startRealtime(context: ModelContext) {
        realtimeContext = context
        guard isSupabaseConfigured, realtimeChannel == nil, let client = try? supabase() else { return }
        let workspace = workspaceID
        let channel = client.channel("earnline:\(workspace)")
        realtimeChannel = channel
        let stream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            filter: .eq("workspace_id", value: workspace)
        )
        realtimeTask = Task { @MainActor [weak self] in
            await channel.subscribe()
            for await _ in stream {
                self?.handleRealtimeChange()
            }
        }
    }

    private func handleRealtimeChange() {
        guard let realtimeContext else { return }
        queueSync(context: realtimeContext)
    }

    private func restartRealtime() {
        let context = realtimeContext
        stopRealtime()
        if let context { startRealtime(context: context) }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel = realtimeChannel {
            realtimeChannel = nil
            let client = supabaseClient
            Task { await client?.removeChannel(channel) }
        }
    }

    private var rateDecimal: Decimal {
        Decimal(string: String(rate), locale: Locale(identifier: "en_US_POSIX"))
            ?? Decimal(Self.defaultExchangeRate)
    }

    nonisolated static func validExchangeRate(_ value: Double, fallback: Double = defaultExchangeRate) -> Double {
        if value.isFinite, value > 0 {
            return value
        }
        if fallback.isFinite, fallback > 0 {
            return fallback
        }
        return defaultExchangeRate
    }

    nonisolated static func normalizedCurrencyCode(_ code: String?, fallback: String) -> String {
        let normalized = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if supportedCurrencyCodes.contains(normalized) {
            return normalized
        }
        return supportedCurrencyCodes.contains(fallback) ? fallback : defaultBaseCurrencyCode
    }

    nonisolated static func replacementCurrencyCode(excluding code: String) -> String {
        supportedCurrencyCodes.first { $0 != code } ?? defaultSecondaryCurrencyCode
    }
}

extension Decimal {
    func rounded(_ scale: Int = 0) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
