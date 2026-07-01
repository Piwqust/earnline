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
        self.decimal = try container.decode(Decimal.self)
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

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func timestampString(_ date: Date) -> String {
        timestampWithFractionalSeconds().string(from: date)
    }

    static func parseTimestamp(_ value: String) -> Date {
        timestampWithFractionalSeconds().date(from: value)
            ?? timestamp().date(from: value)
            ?? Date()
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter().string(from: date)
    }

    static func parseDay(_ value: String) -> Date {
        dayFormatter().date(from: value) ?? Date()
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
