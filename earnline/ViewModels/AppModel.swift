import SwiftUI
import Observation
import SwiftData
import Supabase

/// App-wide UI state + currency settings (persisted in UserDefaults).
@MainActor
@Observable
final class AppModel {
    var baseCurrencyCode: String {
        didSet { defaults.set(baseCurrencyCode, forKey: "baseCurrencyCode") }
    }
    var secondaryCurrencyCode: String {
        didSet { defaults.set(secondaryCurrencyCode, forKey: "secondaryCurrencyCode") }
    }
    /// Secondary units per 1 base unit (e.g. RUB per USD).
    var rate: Double {
        didSet { defaults.set(rate, forKey: "rate") }
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
    var signedInEmail: String?
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

    init() {
        baseCurrencyCode = defaults.string(forKey: "baseCurrencyCode") ?? "USD"
        secondaryCurrencyCode = defaults.string(forKey: "secondaryCurrencyCode") ?? "RUB"
        let r = defaults.double(forKey: "rate")
        rate = r > 0 ? r : 98
        supabaseURLString = defaults.string(forKey: "supabaseURLString") ?? SupabaseProjectDefaults.url
        supabaseKey = defaults.string(forKey: "supabaseKey") ?? SupabaseProjectDefaults.publishableKey
        lastSyncAt = defaults.object(forKey: "lastSyncAt") as? Date
    }

    // MARK: Currency

    /// Convert an entry amount into the base currency.
    func toBase(_ amount: Decimal, code: String) -> Decimal {
        if code == baseCurrencyCode { return amount }
        if code == secondaryCurrencyCode { return amount / Decimal(rate) }
        return amount // unknown currency: treat 1:1
    }

    /// The secondary-currency value for a base amount.
    func secondary(_ base: Decimal) -> Decimal { base * Decimal(rate) }

    func primaryString(_ base: Decimal) -> String {
        CurrencyFormatter.string(base, code: baseCurrencyCode)
    }
    func secondaryString(_ base: Decimal) -> String {
        CurrencyFormatter.string(secondary(base).rounded(), code: secondaryCurrencyCode)
    }

    // MARK: Grouping & totals

    func entries(of client: Client, in month: Date) -> [Entry] {
        client.entries
            .filter { sameMonth($0.date, month) }
            .sorted { $0.sortIndex == $1.sortIndex ? $0.createdAt > $1.createdAt : $0.sortIndex < $1.sortIndex }
    }

    func total(of client: Client, in month: Date) -> Decimal {
        entries(of: client, in: month).reduce(Decimal.zero) { $0 + toBase($1.amount, code: $1.currencyCode) }
    }

    func clientsWithEntries(_ clients: [Client], in month: Date) -> [Client] {
        clients
            .filter { !entries(of: $0, in: month).isEmpty }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    func monthTotal(_ clients: [Client], in month: Date) -> Decimal {
        clients.reduce(Decimal.zero) { $0 + total(of: $1, in: month) }
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
    }

    func refreshSupabaseSession() async {
        guard isSupabaseConfigured else {
            signedInEmail = nil
            syncMessage = "Offline"
            return
        }
        do {
            let user = try await supabase().auth.user()
            signedInEmail = user.email
            syncMessage = "Signed in"
            syncError = nil
        } catch {
            signedInEmail = nil
            syncMessage = "Not signed in"
        }
    }

    func signIn(email: String, password: String) async {
        guard isSupabaseConfigured else {
            syncError = "Add your Supabase URL and publishable key first."
            return
        }
        do {
            try await supabase().auth.signIn(email: email, password: password)
            await refreshSupabaseSession()
        } catch {
            syncError = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        guard isSupabaseConfigured else {
            syncError = "Add your Supabase URL and publishable key first."
            return
        }
        do {
            try await supabase().auth.signUp(email: email, password: password)
            await refreshSupabaseSession()
            if signedInEmail == nil {
                syncMessage = "Check email"
            }
        } catch {
            syncError = error.localizedDescription
        }
    }

    func signOut() async {
        guard isSupabaseConfigured else { return }
        do {
            try await supabase().auth.signOut()
            signedInEmail = nil
            syncMessage = "Signed out"
        } catch {
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
            let completedAt = try await SyncCoordinator.sync(context: context, client: supabase())
            lastSyncAt = completedAt
            syncMessage = "Synced"
            try? context.save()
        } catch {
            syncMessage = "Needs sync"
            syncError = error.localizedDescription
        }
        isSyncing = false
    }

    func queueSync(context: ModelContext) {
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
        signedInEmail = nil
        syncMessage = isSupabaseConfigured ? "Not signed in" : "Offline"
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
