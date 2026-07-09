import SwiftUI
import Observation
import SwiftData
import Supabase
import Network

/// App-wide UI state + currency settings (persisted in UserDefaults).
@MainActor
@Observable
final class AppModel {
    /// UI automation must not inherit a real device's lock state or start a
    /// live personal-workspace sync. This launch argument is set exclusively by
    /// the UI-test target and leaves normal app launches unchanged.
    nonisolated static var isRunningUIAutomation: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
    nonisolated static let supportedCurrencyCodes = ["USD", "EUR", "GBP", "RUB", "UAH"]
    nonisolated static let defaultBaseCurrencyCode = "USD"
    nonisolated static let defaultSecondaryCurrencyCode = "RUB"
    nonisolated static let defaultExchangeRate = 83.0
    nonisolated static let productionWorkspaceID = "earnline-personal"
    nonisolated static let testWorkspaceID = "earnline-dev"

    enum WorkspaceEnvironment: String, CaseIterable, Identifiable {
        case production
        case test

        var id: String { rawValue }

        var workspaceID: String {
            switch self {
            case .production: AppModel.productionWorkspaceID
            case .test: AppModel.testWorkspaceID
            }
        }

        var title: String {
            switch self {
            case .production: String(localized: "Production")
            case .test: String(localized: "Test")
            }
        }

        /// Preloaded Supabase project this environment syncs to. Production and
        /// Test point at separate Supabase databases, so their rows never mix.
        var defaultSupabaseConfig: SupabaseProjectDefaults.ProjectConfig {
            switch self {
            case .production: SupabaseProjectDefaults.production
            case .test: SupabaseProjectDefaults.test
            }
        }

        var storeName: String { "earnline-\(rawValue)" }
    }

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
            defaults.set(supabaseURLString, forKey: workspaceDefaultKey("supabaseURLString"))
            resetSupabaseClient()
        }
    }
    var supabaseKey: String {
        didSet {
            defaults.set(supabaseKey, forKey: workspaceDefaultKey("supabaseKey"))
            resetSupabaseClient()
        }
    }
    var workspaceEnvironment: WorkspaceEnvironment {
        didSet {
            guard workspaceEnvironment != oldValue else { return }
            defaults.set(workspaceEnvironment.rawValue, forKey: "workspaceEnvironment")
            workspaceID = workspaceEnvironment.workspaceID
            defaults.set(workspaceID, forKey: "workspaceID")
            // Each environment points at its own Supabase project — swap the
            // URL/key over to the new one before rebuilding the client.
            loadWorkspaceSupabaseConfig()
            loadWorkspaceSyncState()
            detachWorkspaceStore()
            resetSupabaseClient()
        }
    }
    private(set) var workspaceID: String

    /// System / Light / Dark — the standard three-way appearance choice Apple
    /// apps offer. `system` follows the device scheme (`.unspecified`).
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: String(localized: "System")
            case .light: String(localized: "Light")
            case .dark: String(localized: "Dark")
            }
        }

        var uiStyle: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }
    /// Accent for interactive elements — ChatGPT's "Accent color" setting.
    /// Applied at the root via `.tint`, so everything tint-following updates.
    var accent: Theme.Accent {
        didSet { defaults.set(accent.rawValue, forKey: "accentColor") }
    }
    var accentColor: Color { accent.color }
    /// Face ID / passcode lock on backgrounding — opt-in via Settings.
    var requireAppLock: Bool {
        didSet { defaults.set(requireAppLock, forKey: "requireAppLock") }
    }
    private(set) var isLocked = false
    var isSyncing = false
    var syncMessage = String(localized: "Offline")
    var syncError: String?
    /// Number of remote edits/deletes that changed after this device's last
    /// observed server version. These require an explicit user choice rather
    /// than a silent last-device-wins overwrite.
    private(set) var syncConflictCount = 0
    /// When the last sync completed — display only ("Last sync" in Settings).
    var lastSyncAt: Date? {
        didSet { defaults.set(lastSyncAt, forKey: workspaceDefaultKey("lastSyncAt")) }
    }
    /// Incremental cursor for server-managed row `updated_at` values.
    var syncCursor: Date? {
        didSet { defaults.set(syncCursor, forKey: workspaceDefaultKey("syncCursor")) }
    }
    var workspaceDisplayName: String {
        workspaceEnvironment.title
    }

    /// The month currently under the top of the scroll — shown in the summary pill.
    var displayedMonth: Date = DateFormat.monthStart(of: .now)

    /// Whether the Settings sheet is up. Lives here — and the sheet is
    /// presented from `WorkspaceContainerHost` — because switching the
    /// workspace recreates `LedgerView` via `.id`, and a `@State` flag there
    /// would tear Settings down mid-interaction the moment the user flips the
    /// Production/Test picker inside it.
    var showSettings = false

    private let defaults = UserDefaults.standard
    @ObservationIgnored private var supabaseClient: SupabaseClient?
    @ObservationIgnored private var queuedSyncTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeChannel: RealtimeChannelV2?
    /// The client that owns `realtimeChannel` — kept so teardown can remove the
    /// channel even after `supabaseClient` has been reset to nil.
    @ObservationIgnored private var realtimeClient: SupabaseClient?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeContext: ModelContext?
    @ObservationIgnored private var configRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var followUpSyncRequested = false
    /// Bumped on every workspace detach. An in-flight `syncNow` snapshots the
    /// generation before its await and discards its results if the workspace
    /// changed underneath it — otherwise a Production pass finishing after a
    /// switch to Test would write its cursor under Test's keys.
    @ObservationIgnored private var syncGeneration = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var invokedByRetry = false
    @ObservationIgnored private var lastSyncFailed = false
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var pathMonitorStarted = false
    @ObservationIgnored private var pathWasSatisfied = true
    @ObservationIgnored private var lockWindow: UIWindow?
    @ObservationIgnored private var isUnlocking = false

    init() {
        let resolvedBaseCurrencyCode = Self.normalizedCurrencyCode(defaults.string(forKey: "baseCurrencyCode"),
                                                                   fallback: Self.defaultBaseCurrencyCode)
        baseCurrencyCode = resolvedBaseCurrencyCode
        let savedSecondary = Self.normalizedCurrencyCode(defaults.string(forKey: "secondaryCurrencyCode"),
                                                         fallback: Self.defaultSecondaryCurrencyCode)
        secondaryCurrencyCode = savedSecondary == resolvedBaseCurrencyCode
            ? Self.replacementCurrencyCode(excluding: resolvedBaseCurrencyCode)
            : savedSecondary
        var r = defaults.double(forKey: "rate")
        // One-time reset to the current shipped rate (83 ₽/$): values carried
        // over from older builds move to the new default on first launch;
        // afterwards whatever the user types always wins.
        if !defaults.bool(forKey: "didApplyDefaultRate83") {
            r = Self.defaultExchangeRate
            defaults.set(r, forKey: "rate")
            defaults.set(true, forKey: "didApplyDefaultRate83")
        }
        rate = Self.validExchangeRate(r, fallback: Self.defaultExchangeRate)
        let savedEnvironment = defaults.string(forKey: "workspaceEnvironment").flatMap(WorkspaceEnvironment.init(rawValue:))
        let resolvedEnvironment = savedEnvironment ?? .production
        // Supabase config is per environment: seed each field from its stored
        // per-workspace value, falling back to the project preloaded for that
        // environment so the app syncs out of the box with nothing to paste.
        let config = resolvedEnvironment.defaultSupabaseConfig
        supabaseURLString = defaults.string(forKey: "supabaseURLString.\(resolvedEnvironment.rawValue)") ?? config.url
        supabaseKey = defaults.string(forKey: "supabaseKey.\(resolvedEnvironment.rawValue)") ?? config.publishableKey
        workspaceEnvironment = resolvedEnvironment
        workspaceID = resolvedEnvironment.workspaceID
        defaults.set(resolvedEnvironment.rawValue, forKey: "workspaceEnvironment")
        defaults.set(resolvedEnvironment.workspaceID, forKey: "workspaceID")
        let workspaceKeySuffix = resolvedEnvironment.rawValue
        let savedLastSyncAt = defaults.object(forKey: "lastSyncAt.\(workspaceKeySuffix)") as? Date
            ?? defaults.object(forKey: "lastSyncAt") as? Date
        lastSyncAt = savedLastSyncAt
        // Migrate installs from before the cursor/display split and before
        // per-workspace stores: seed the active workspace from the old keys.
        let savedSyncCursor = defaults.object(forKey: "syncCursor.\(workspaceKeySuffix)") as? Date
            ?? defaults.object(forKey: "syncCursor") as? Date
            ?? savedLastSyncAt
        syncCursor = savedSyncCursor
        if let saved = defaults.string(forKey: "appearanceMode").flatMap(AppearanceMode.init(rawValue:)) {
            appearanceMode = saved
        } else if let legacyDark = defaults.object(forKey: "prefersDarkMode") as? Bool {
            // Migrate the old binary toggle without changing what the user
            // sees: an explicit choice stays explicit. Fresh installs follow
            // the system, as Apple's own apps do.
            appearanceMode = legacyDark ? .dark : .light
        } else {
            appearanceMode = .system
        }
        accent = Theme.Accent(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .blue
        requireAppLock = defaults.bool(forKey: "requireAppLock")
        syncMessage = isSupabaseConfigured ? String(localized: "Ready") : String(localized: "Offline")
    }

    // MARK: App lock

    /// Cold launches start covered when the lock is on; the biometric prompt
    /// fires as soon as the window exists (called from the root `.task`).
    func lockOnLaunchIfNeeded() {
        guard requireAppLock else { return }
        isLocked = true
        showLockWindow()
        attemptUnlockIfNeeded()
    }

    /// Called on backgrounding — covers the content before the app-switcher
    /// snapshot is taken, so amounts never show in the multitasking UI.
    func lockIfNeeded() {
        guard requireAppLock, !isLocked else { return }
        isLocked = true
        showLockWindow()
    }

    /// Called on `.inactive` — the app-switcher snapshot is taken while the
    /// scene is still inactive, before `.background` fires, so waiting for
    /// backgrounding briefly exposed the ledger in the multitasking UI. This
    /// shows the cover *without* committing the lock: swiping away Control
    /// Center or an incoming-call banner returns straight to content, no
    /// re-authentication.
    func coverIfNeeded() {
        guard requireAppLock, !isLocked else { return }
        showLockWindow()
    }

    /// Called on `.active` — removes an uncommitted privacy cover. A real
    /// lock (set on `.background`) stays up until `attemptUnlockIfNeeded`
    /// succeeds.
    func uncoverIfNeeded() {
        guard !isLocked else { return }
        hideLockWindow()
    }

    /// Called on activation and by the lock screen's Unlock button.
    func attemptUnlockIfNeeded() {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await AppLockAuth.evaluate(reason: String(localized: "Unlock your income ledger")) {
                self.isLocked = false
                self.hideLockWindow()
            }
            self.isUnlocking = false
        }
    }

    /// The lock lives in its own alert-level window for the same reason dark
    /// mode is a window-level override: a SwiftUI overlay in the root view
    /// sits *under* presented sheets, and the lock must cover those too.
    private func showLockWindow() {
        guard lockWindow == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState != .unattached }) ?? scenes.first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = appearanceMode.uiStyle
        window.rootViewController = UIHostingController(
            rootView: LockScreenView { [weak self] in self?.attemptUnlockIfNeeded() }
        )
        window.makeKeyAndVisible()
        lockWindow = window
    }

    private func hideLockWindow() {
        guard let window = lockWindow else { return }
        // Tear the alert-level window down in UIKit's expected order. Leaving
        // its hosting controller attached while dropping the last window
        // reference produced unbalanced appearance transitions in tests and
        // could leave the main scene without a key window after unlock.
        window.resignKey()
        window.isHidden = true
        window.rootViewController = nil
        lockWindow = nil
    }

    // MARK: Undo delete

    /// The last delete, held for a short window so the toast can reverse it.
    var undoableDelete: UndoableDelete?
    @ObservationIgnored private var undoExpiryTask: Task<Void, Never>?

    /// Call after the delete has actually saved — a toast for a delete that
    /// failed to persist would offer to undo nothing.
    func stageUndo(_ delete: UndoableDelete) {
        undoableDelete = delete
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undoableDelete = nil
        }
    }

    /// Returns `nil` on success or the failure message — surface it with
    /// `.saveErrorAlert` so a failed restore never passes for a successful one.
    @discardableResult
    func performUndo(context: ModelContext) -> String? {
        guard let undoableDelete else { return nil }
        undoExpiryTask?.cancel()
        self.undoableDelete = nil
        do {
            try undoableDelete.restore(in: context)
            try context.save()
            queueSync(context: context)
            return nil
        } catch {
            context.rollback()
            return error.localizedDescription
        }
    }

    // MARK: Appearance

    /// Pushes the appearance choice onto every window of every scene.
    /// `preferredColorScheme` only styles the presentation it's declared in, so
    /// sheets (Search, Insights, Pending, Settings), alerts, and menus kept
    /// following the *system* appearance — the toggle looked broken whenever
    /// the system scheme disagreed. A window-level override covers them all;
    /// `.system` clears the override (`.unspecified`) so the device scheme
    /// flows through untouched.
    func applyAppearance() {
        let style = appearanceMode.uiStyle
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
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
    func canConvert(_ code: String) -> Bool { conversionRate(from: code) != nil }

    /// Convert an entry amount into the base currency.
    func toBase(_ amount: Decimal, code: String) -> Decimal {
        if code == baseCurrencyCode { return amount }
        if code == secondaryCurrencyCode { return amount / rateDecimal }
        // A third currency is a valid imported or synced state, but adding its
        // raw units to a base-currency total fabricates a financial result.
        // Callers retain and display the entry's original amount; consolidated
        // totals exclude it until a conversion rate is available.
        #if DEBUG
        print("⚠️ toBase: no rate for \(code); excluding it from consolidated totals.")
        #endif
        return .zero
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
        // A running sum doesn't care about order, so skip the filtered-array
        // allocation and the sort that `earnedEntries` does — this runs per
        // client, per visible month, and (×6) on every summary refresh.
        client.entries.reduce(Decimal.zero) { sum, entry in
            guard entry.status.isIncludedInEarnedTotals, sameMonth(entry.date, month) else { return sum }
            return sum + toBase(entry.amount, code: entry.currencyCode)
        }
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

    /// Every client that earned over the last `lastNMonths` months, highest
    /// first, dropping clients with nothing earned — the full breakdown behind
    /// the Top clients composition bar.
    func clientTotals(_ clients: [Client], lastNMonths: Int = 12) -> [(client: Client, total: Decimal)] {
        let months = monthlySeries(clients, lastNMonths: lastNMonths).map(\.month)
        return clients
            .map { client in
                (client: client, total: months.reduce(Decimal.zero) { $0 + total(of: client, in: $1) })
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    /// The `limit` highest-earning clients over the window.
    func topClients(_ clients: [Client], lastNMonths: Int = 12, limit: Int = 3) -> [(client: Client, total: Decimal)] {
        Array(clientTotals(clients, lastNMonths: lastNMonths).prefix(limit))
    }

    /// Month-over-month change in earned revenue across the last `lastNMonths`
    /// months: each month's earned total minus the prior month's. An extra
    /// leading month is fetched so the first bar has a real baseline.
    func monthlyDeltas(_ clients: [Client], lastNMonths: Int = 12) -> [(month: Date, delta: Decimal, total: Decimal)] {
        let series = monthlySeries(clients, lastNMonths: lastNMonths + 1)
        guard series.count >= 2 else {
            return series.map { (month: $0.month, delta: $0.total, total: $0.total) }
        }
        return (1..<series.count).map { index in
            (month: series[index].month,
             delta: series[index].total - series[index - 1].total,
             total: series[index].total)
        }
    }

    /// Straight-line month-end projection for the running month: the earned
    /// total so far scaled up to the full month. Nil while there's nothing to
    /// extrapolate — no earnings yet, or the first two days of a month (one
    /// early invoice would project an absurd figure).
    nonisolated static func monthPace(total: Decimal,
                                      now: Date = .now,
                                      calendar: Calendar = .current) -> Decimal? {
        guard total > 0 else { return nil }
        let day = calendar.component(.day, from: now)
        guard day >= 3,
              let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }
        return (total / Decimal(day) * Decimal(daysInMonth)).rounded()
    }

    // MARK: Insights — daily heatmap

    /// How a single line lands on the calendar: the base-currency amount it
    /// contributes per day and the span of days it covers. A *held* line
    /// spreads its amount evenly across every day from its own date through the
    /// hold-release day (inclusive) — the money is "earning" across the wait —
    /// while every other line lands wholly on its date.
    private func heatSpan(of entry: Entry) -> (start: Date, end: Date, perDay: Decimal, dayCount: Int) {
        let calendar = Calendar.current
        let base = toBase(entry.amount, code: entry.currencyCode)
        let start = calendar.startOfDay(for: entry.date)
        guard let hold = entry.holdUntil else { return (start, start, base, 1) }
        let end = calendar.startOfDay(for: hold)
        guard end > start else { return (start, start, base, 1) }
        let count = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return (start, end, base / Decimal(count), count)
    }

    /// Earned base-currency amount for each calendar day in `[startDay, endDay]`,
    /// with held lines distributed evenly over their span. Canceled lines are
    /// excluded; days with nothing earned are simply absent from the result.
    /// Keys are start-of-day, matching what the heatmap looks up.
    func dailyEarnings(_ clients: [Client], from startDay: Date, through endDay: Date) -> [Date: Decimal] {
        let calendar = Calendar.current
        let lo = calendar.startOfDay(for: startDay)
        let hi = calendar.startOfDay(for: endDay)
        guard lo <= hi else { return [:] }
        var map: [Date: Decimal] = [:]
        for client in clients {
            for entry in client.entries where entry.status.isIncludedInEarnedTotals {
                let span = heatSpan(of: entry)
                var day = max(span.start, lo)
                let last = min(span.end, hi)
                while day <= last {
                    map[day, default: .zero] += span.perDay
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
        }
        return map
    }

    /// The lines earning on `day`, largest slice first, each paired with the
    /// base-currency amount it contributes that day (a full amount, or one even
    /// slice of a held line). Powers the tapped-day breakdown.
    func dayContributions(on day: Date, clients: [Client]) -> [(entry: Entry, amount: Decimal, isHeldSlice: Bool)] {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: day)
        var rows: [(entry: Entry, amount: Decimal, isHeldSlice: Bool)] = []
        for client in clients {
            for entry in client.entries where entry.status.isIncludedInEarnedTotals {
                let span = heatSpan(of: entry)
                if target >= span.start && target <= span.end {
                    rows.append((entry: entry, amount: span.perDay, isHeldSlice: span.dayCount > 1))
                }
            }
        }
        return rows.sorted { $0.amount > $1.amount }
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
        let urlText = supabaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText),
              url.scheme?.lowercased() == "https",
              url.host() != nil else { return false }
        return !supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshSupabaseSession() async {
        guard isSupabaseConfigured else {
            syncMessage = String(localized: "Offline")
            return
        }
        do {
            _ = try supabase()
            syncMessage = String(localized: "Ready")
            syncError = nil
        } catch {
            syncMessage = String(localized: "Needs setup")
            syncError = error.localizedDescription
        }
    }

    func syncNow(context: ModelContext,
                 conflictResolution: SyncCoordinator.ConflictResolution = .requireUserChoice) async {
        guard isSupabaseConfigured else {
            syncMessage = String(localized: "Offline")
            return
        }
        guard !isSyncing else {
            // A pass is already on the wire — run another when it finishes so
            // edits made mid-flight are pushed rather than dropped.
            followUpSyncRequested = true
            return
        }
        // Any pass supersedes a pending retry; an externally triggered one
        // (edit, foreground, realtime) also restarts the backoff ladder.
        retryTask?.cancel()
        if !invokedByRetry { retryAttempt = 0 }
        invokedByRetry = false
        // Demo rows seeded while sync was unconfigured must not leak into a
        // real workspace — drop the never-synced ones before the first push.
        SampleData.purgeAutoSeededDemoIfNeeded(context)
        let generation = syncGeneration
        isSyncing = true
        syncMessage = String(localized: "Syncing...")
        syncError = nil
        do {
            let nextCursor = try await SyncCoordinator.sync(context: context,
                                                            client: supabase(),
                                                            workspaceID: workspaceID,
                                                            lastPulledAt: syncCursor,
                                                            conflictResolution: conflictResolution)
            guard generation == syncGeneration else {
                finishStaleSyncPass()
                return
            }
            syncCursor = nextCursor.rowUpdatedAt
            lastSyncAt = Date()
            syncMessage = String(localized: "Synced")
            try context.save()
            refreshPendingReminders(context: context)
            retryAttempt = 0
            lastSyncFailed = false
            syncConflictCount = 0
        } catch {
            guard generation == syncGeneration else {
                finishStaleSyncPass()
                return
            }
            context.rollback()
            if let conflict = error as? SyncCoordinator.SyncConflictError {
                syncConflictCount = conflict.count
                syncMessage = String(localized: "Resolve conflict")
                syncError = conflict.localizedDescription
                lastSyncFailed = false
            } else {
                syncMessage = String(localized: "Needs sync")
                syncError = error.localizedDescription
                lastSyncFailed = true
                scheduleRetrySync(context: context)
            }
        }
        isSyncing = false
        if followUpSyncRequested {
            followUpSyncRequested = false
            await syncNow(context: context)
        }
    }

    /// An in-flight pass outlived a workspace switch: drop its results and
    /// state writes. If a sync was requested for the *new* workspace while the
    /// stale pass held `isSyncing`, run it now against the current store.
    private func finishStaleSyncPass() {
        isSyncing = false
        if followUpSyncRequested {
            followUpSyncRequested = false
            if let context = realtimeContext { queueSync(context: context) }
        }
    }

    /// Replace the local SwiftData cache with the selected Supabase workspace.
    /// This intentionally does not enqueue tombstones: the user is switching
    /// sources of truth, not deleting remote income rows.
    @discardableResult
    func resetLocalDataAndPull(context: ModelContext) async -> String? {
        guard isSupabaseConfigured else {
            syncMessage = String(localized: "Offline")
            return String(localized: "Add the Supabase URL and publishable key first.")
        }
        syncGeneration += 1 // a pass already on the wire must not restore the old cursor
        queuedSyncTask?.cancel()
        retryTask?.cancel()
        followUpSyncRequested = false
        retryAttempt = 0
        invokedByRetry = false
        lastSyncFailed = false
        do {
            try clearLocalStore(context)
            syncCursor = nil
            lastSyncAt = nil
            defaults.set(false, forKey: SampleData.autoSeededDemoKey)
            await syncNow(context: context)
            return syncError
        } catch {
            syncMessage = String(localized: "Needs sync")
            syncError = error.localizedDescription
            return error.localizedDescription
        }
    }

    func queueSync(context: ModelContext) {
        queuedSyncTask?.cancel()
        queuedSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            self.refreshPendingReminders(context: context)
            await self.syncNow(context: context)
        }
    }

    /// The user has reviewed the conflict warning and intentionally wants this
    /// iPhone's dirty rows to replace the remote copies.
    func keepLocalConflictChanges(context: ModelContext) async {
        await syncNow(context: context, conflictResolution: .preferLocal)
    }

    func detachWorkspaceStore() {
        syncGeneration += 1
        queuedSyncTask?.cancel()
        retryTask?.cancel()
        configRefreshTask?.cancel()
        followUpSyncRequested = false
        retryAttempt = 0
        invokedByRetry = false
        lastSyncFailed = false
        realtimeContext = nil
        stopRealtime()
    }

    // MARK: Persistence

    /// The one persistence path: commit pending changes and kick the debounced
    /// sync. Returns `nil` on success, or a user-facing message on failure —
    /// assign it to the caller's error state and surface it with
    /// `.saveErrorAlert`. Every screen saves through here so the save + sync +
    /// error-reporting behaviour is identical everywhere.
    @discardableResult
    func save(_ context: ModelContext) -> String? {
        do {
            try context.save()
            queueSync(context: context)
            return nil
        } catch {
            // A save error must leave the screen exactly as it was before the
            // action. Without this rollback, a later unrelated save could
            // commit an insert/edit/delete the user was told had failed.
            context.rollback()
            return error.localizedDescription
        }
    }

    private func clearLocalStore(_ context: ModelContext) throws {
        for entry in try context.fetch(FetchDescriptor<Entry>()) {
            context.delete(entry)
        }
        for heading in try context.fetch(FetchDescriptor<Heading>()) {
            context.delete(heading)
        }
        for tombstone in try context.fetch(FetchDescriptor<SyncTombstone>()) {
            context.delete(tombstone)
        }
        for client in try context.fetch(FetchDescriptor<Client>()) {
            context.delete(client)
        }
        try context.save()
    }

    /// Delete an entry through the standard tombstone → save → undo flow, so a
    /// deletion looks the same whether it comes from the ledger, a client, or
    /// the pending list. Returns `nil` on success (with the undo staged) or the
    /// error message on failure.
    @discardableResult
    func delete(_ entry: Entry, context: ModelContext) -> String? {
        let snapshot = UndoableDelete.entry(EntrySnapshot(entry))
        SyncDeleteQueue.enqueue(.entry, id: entry.id, in: context)
        withAnimation(.snappy) { context.delete(entry) }
        let error = save(context)
        if error == nil { stageUndo(snapshot) }
        return error
    }

    // MARK: Retry & reconnect

    /// A failed pass retries itself with growing delays, then gives up until
    /// the next external trigger (edit, foreground, realtime, reconnect) —
    /// endless polling against a dead endpoint would just burn battery.
    private func scheduleRetrySync(context: ModelContext) {
        guard let delay = Self.retryDelay(attempt: retryAttempt) else { return }
        retryAttempt += 1
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isSupabaseConfigured, !self.isSyncing else { return }
            self.invokedByRetry = true
            await self.syncNow(context: context)
        }
    }

    /// Backoff ladder: 5 s → 15 s → 45 s → 120 s, then nil (stop).
    nonisolated static func retryDelay(attempt: Int) -> Duration? {
        let delays: [Duration] = [.seconds(5), .seconds(15), .seconds(45), .seconds(120)]
        guard delays.indices.contains(attempt) else { return nil }
        return delays[attempt]
    }

    /// Sync as soon as connectivity returns after a failed pass, instead of
    /// sitting on "Needs sync" until the user happens to touch something.
    private func startPathMonitorIfNeeded() {
        guard !pathMonitorStarted else { return }
        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathChange(satisfied: satisfied)
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "earnline.path-monitor"))
    }

    private func handlePathChange(satisfied: Bool) {
        let cameBackOnline = satisfied && !pathWasSatisfied
        pathWasSatisfied = satisfied
        guard cameBackOnline, lastSyncFailed, let context = realtimeContext else { return }
        queueSync(context: context)
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
        syncMessage = isSupabaseConfigured ? String(localized: "Ready") : String(localized: "Offline")
        scheduleConfigRefresh()
    }

    private func workspaceDefaultKey(_ key: String) -> String {
        "\(key).\(workspaceEnvironment.rawValue)"
    }

    private func loadWorkspaceSyncState() {
        lastSyncAt = defaults.object(forKey: workspaceDefaultKey("lastSyncAt")) as? Date
        syncCursor = defaults.object(forKey: workspaceDefaultKey("syncCursor")) as? Date
    }

    /// Load the Supabase URL/key for the active environment: the user's stored
    /// value for that workspace, or the project preloaded for it. Assigning
    /// these fires their `didSet`s, which persist the values under the new
    /// workspace's keys and rebuild the client.
    private func loadWorkspaceSupabaseConfig() {
        let config = workspaceEnvironment.defaultSupabaseConfig
        supabaseURLString = defaults.string(forKey: workspaceDefaultKey("supabaseURLString")) ?? config.url
        supabaseKey = defaults.string(forKey: workspaceDefaultKey("supabaseKey")) ?? config.publishableKey
    }

    /// The Settings fields fire their didSets on every keystroke — debounce
    /// before rebuilding the realtime subscription, and kick off a sync so a
    /// freshly configured workspace pulls without waiting for a manual "Sync
    /// now" or the next edit.
    private func scheduleConfigRefresh() {
        guard realtimeContext != nil else { return }
        configRefreshTask?.cancel()
        configRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.restartRealtime()
            if let context = self.realtimeContext, self.isSupabaseConfigured {
                await self.syncNow(context: context)
            }
        }
    }

    // MARK: Realtime

    /// Subscribe to workspace changes and trigger a debounced sync on any remote
    /// insert/update/delete. One schema-wide channel filtered by `workspace_id`
    /// covers clients, entries, headings, and tombstones.
    func startRealtime(context: ModelContext) {
        realtimeContext = context
        startPathMonitorIfNeeded()
        guard isSupabaseConfigured, realtimeChannel == nil, let client = try? supabase() else { return }
        let workspace = workspaceID
        let channel = client.channel("earnline:\(workspace)")
        realtimeChannel = channel
        realtimeClient = client
        let stream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            filter: .eq("workspace_id", value: workspace)
        )
        realtimeTask = Task { @MainActor [weak self] in
            do {
                try await channel.subscribeWithError()
            } catch {
                // Realtime is an optimization, not a reason to hide a failed
                // subscription. The next foreground/manual sync still works.
                self?.syncError = "Realtime updates unavailable: \(error.localizedDescription)"
            }
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
        // Tear down against the client that created the channel — after a
        // config change `supabaseClient` is already nil, and skipping the
        // removal leaked a live subscription per change.
        let client = realtimeClient
        realtimeClient = nil
        if let channel = realtimeChannel {
            realtimeChannel = nil
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
