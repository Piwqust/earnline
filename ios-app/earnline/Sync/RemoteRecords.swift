import Foundation

struct SyncMoney: Codable, Equatable {
    let decimal: Decimal

    init(_ decimal: Decimal) {
        self.decimal = decimal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self),
           let decimal = Decimal(string: raw, locale: Self.locale) {
            self.decimal = decimal
            return
        }
        // PostgREST serializes numeric columns as JSON numbers, and JSONDecoder
        // routes those through Double, which can leave binary dust (99.99 →
        // 99.9899…). Amounts are numeric(14,2) on the wire, so snap to 2 dp.
        self.decimal = try container.decode(Decimal.self).rounded(2)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.string(from: decimal))
    }

    private static let locale = Locale(identifier: "en_US_POSIX")

    private static func makeFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter
    }

    static func string(from value: Decimal) -> String {
        makeFormatter().string(from: value as NSDecimalNumber)
            ?? NSDecimalNumber(decimal: value).stringValue
    }
}

/// Precision-safe exchange-rate value. PostgREST may return `numeric` as a
/// JSON number, so decode through `Decimal` and only convert to `Double` at the
/// AppModel boundary. Encoding as a decimal string avoids binary floating-point
/// dust on writes.
struct SyncRate: Codable, Equatable {
    let decimal: Decimal

    init(_ value: Double) {
        decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
            ?? Decimal(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self),
           let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) {
            decimal = value
        } else {
            decimal = try container.decode(Decimal.self).rounded(8)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: decimal).stringValue)
    }

    var doubleValue: Double { NSDecimalNumber(decimal: decimal).doubleValue }
}

enum SyncError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Supabase is not configured."
        }
    }
}

enum SyncDateCodec {
    private static func timestampWithFractionalSeconds() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func timestamp() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    /// Wire invariant (shared with the web client): a `yyyy-MM-dd` value IS the
    /// calendar day the user sees — not an instant. So days are formatted from
    /// and parsed into the *local* calendar. Formatting in UTC shifted every
    /// local-midnight date (DatePicker, parsed hold dates) to the previous day
    /// for UTC-positive timezones, and parsing in UTC displayed every synced
    /// date a day early for UTC-negative ones.
    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func timestampString(_ date: Date) -> String {
        timestampWithFractionalSeconds().string(from: date)
    }

    /// `nil` for malformed wire values. Falling back to `Date()` here used to
    /// disguise bad rows as *fresh* ones — inflating conflict resolution and
    /// advancing the sync cursor past legitimately older remote writes. The
    /// coordinator now skips rows it can't date instead.
    static func parseTimestamp(_ value: String) -> Date? {
        timestampWithFractionalSeconds().date(from: value)
            ?? timestamp().date(from: value)
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter().string(from: date)
    }

    /// `nil` for malformed wire values (the old fallback silently rewrote the
    /// row's date to *today*). Valid days are anchored at 12:00 local rather
    /// than midnight: the web client stores days timezone-independently, and
    /// noon keeps the extracted calendar day stable if the device later
    /// re-encodes the date from a timezone up to ±11 hours away — a
    /// local-midnight anchor flips to the previous day after eastward travel.
    static func parseDay(_ value: String) -> Date? {
        guard let midnight = dayFormatter().date(from: value) else { return nil }
        return Calendar.current.date(byAdding: .hour, value: 12, to: midnight) ?? midnight
    }
}

struct RemoteClient: Codable, Identifiable {
    let id: UUID
    let workspaceID: String
    let name: String
    let colorHex: String
    let sortIndex: Int
    let createdAt: String
    let updatedAt: String

    init(_ client: Client, workspaceID: String) {
        id = client.id
        self.workspaceID = workspaceID
        name = client.name
        colorHex = client.colorHex
        sortIndex = client.sortIndex
        createdAt = SyncDateCodec.timestampString(client.createdAt)
        updatedAt = SyncDateCodec.timestampString(client.syncUpdatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case name
        case colorHex = "color_hex"
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RemoteProjectIcon: Codable, Identifiable {
    let id: UUID
    let workspaceID: String
    let projectKey: String
    let symbolName: String
    let createdAt: String
    let updatedAt: String

    init(_ preference: ProjectIconPreference, workspaceID: String) {
        id = preference.id
        self.workspaceID = workspaceID
        projectKey = preference.projectKey
        symbolName = preference.symbol.rawValue
        createdAt = SyncDateCodec.timestampString(preference.createdAt)
        updatedAt = SyncDateCodec.timestampString(preference.syncUpdatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case projectKey = "project_key"
        case symbolName = "symbol_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RemoteEntry: Codable, Identifiable {
    let id: UUID
    let workspaceID: String
    let clientID: UUID
    let amount: SyncMoney
    let currencyCode: String
    let project: String?
    let task: String
    let date: String
    let holdUntil: String?
    let status: String
    let sortIndex: Int
    let createdAt: String
    let updatedAt: String

    init?(_ entry: Entry, workspaceID: String) {
        guard let clientID = entry.client?.id else { return nil }
        id = entry.id
        self.workspaceID = workspaceID
        self.clientID = clientID
        amount = SyncMoney(entry.amount)
        currencyCode = entry.currencyCode
        project = entry.project
        task = entry.task
        date = SyncDateCodec.dayString(entry.date)
        holdUntil = entry.holdUntil.map(SyncDateCodec.dayString)
        status = entry.status.rawValue
        sortIndex = entry.sortIndex
        createdAt = SyncDateCodec.timestampString(entry.createdAt)
        updatedAt = SyncDateCodec.timestampString(entry.syncUpdatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case clientID = "client_id"
        case amount
        case currencyCode = "currency_code"
        case project
        case task
        case date
        case holdUntil = "hold_until"
        case status
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RemoteHeading: Codable, Identifiable {
    let id: UUID
    let workspaceID: String
    let title: String
    let date: String
    let sortIndex: Int
    let createdAt: String
    let updatedAt: String

    init(_ heading: Heading, workspaceID: String) {
        id = heading.id
        self.workspaceID = workspaceID
        title = heading.title
        date = SyncDateCodec.dayString(heading.date)
        sortIndex = heading.sortIndex
        createdAt = SyncDateCodec.timestampString(heading.createdAt)
        updatedAt = SyncDateCodec.timestampString(heading.syncUpdatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case title
        case date
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct WorkspaceProfilePayload: Codable, Equatable {
    let workspaceID: String
    let baseCurrencyCode: String
    let secondaryCurrencyCode: String
    let exchangeRate: SyncRate

    init(workspaceID: String,
         baseCurrencyCode: String,
         secondaryCurrencyCode: String,
         exchangeRate: Double) {
        self.workspaceID = workspaceID
        self.baseCurrencyCode = baseCurrencyCode
        self.secondaryCurrencyCode = secondaryCurrencyCode
        self.exchangeRate = SyncRate(exchangeRate)
    }

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case baseCurrencyCode = "base_currency_code"
        case secondaryCurrencyCode = "secondary_currency_code"
        case exchangeRate = "exchange_rate"
    }
}

struct RemoteWorkspaceProfile: Codable, Equatable {
    let workspaceID: String
    let baseCurrencyCode: String
    let secondaryCurrencyCode: String
    let exchangeRate: SyncRate
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case baseCurrencyCode = "base_currency_code"
        case secondaryCurrencyCode = "secondary_currency_code"
        case exchangeRate = "exchange_rate"
        case updatedAt = "updated_at"
    }
}

struct RemoteTombstone: Codable, Identifiable {
    let id: UUID
    let workspaceID: String
    let entity: String
    let recordID: UUID
    let deletedAt: String
    let createdAt: String

    init(_ tombstone: SyncTombstone, workspaceID: String) {
        id = tombstone.id
        self.workspaceID = workspaceID
        entity = tombstone.entityRaw
        recordID = tombstone.recordID
        deletedAt = SyncDateCodec.timestampString(tombstone.deletedAt)
        createdAt = SyncDateCodec.timestampString(tombstone.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case entity
        case recordID = "record_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }
}
