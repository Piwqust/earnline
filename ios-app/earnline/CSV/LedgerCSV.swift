import Foundation

/// The deliberately small interchange format for ledger income rows. It is
/// RFC 4180 CSV encoded as UTF-8; it is not a backup and intentionally does
/// not carry sync IDs, notes, month reviews, or workspace settings.
enum LedgerCSV {
    static let columns = [
        "date", "client", "project", "task", "amount", "currency_code", "status", "hold_date",
    ]

    static let supportedCurrencyCodes: Set<String> = ["USD", "RUB", "EUR", "GBP", "UAH"]

    struct ExportRecord: Hashable {
        var date: Date
        var client: String
        var project: String?
        var task: String
        var amount: Decimal
        var currencyCode: String
        var status: EntryStatus
        var holdDate: Date?

        init(date: Date,
             client: String,
             project: String?,
             task: String,
             amount: Decimal,
             currencyCode: String,
             status: EntryStatus,
             holdDate: Date?) {
            self.date = date
            self.client = client
            self.project = project
            self.task = task
            self.amount = amount
            self.currencyCode = currencyCode
            self.status = status
            self.holdDate = holdDate
        }
    }

    struct ImportedRow: Identifiable, Hashable {
        let rowNumber: Int
        let date: Date
        let client: String
        let project: String?
        let task: String
        let amount: Decimal
        let currencyCode: String
        let status: EntryStatus
        let holdDate: Date?

        var id: Int { rowNumber }

        var duplicateKey: DuplicateKey {
            DuplicateKey(
                date: date,
                client: client,
                project: project,
                task: task,
                amount: amount,
                currencyCode: currencyCode,
                status: status,
                holdDate: holdDate
            )
        }
    }

    /// A semantic identity used only to warn before a duplicate import. It is
    /// intentionally independent of a SwiftData or sync identifier.
    struct DuplicateKey: Hashable {
        fileprivate let dateKey: String
        fileprivate let clientKey: String
        fileprivate let projectKey: String
        fileprivate let taskKey: String
        fileprivate let amount: Decimal
        fileprivate let currencyCode: String
        fileprivate let status: EntryStatus
        fileprivate let holdDateKey: String

        init(date: Date,
             client: String,
             project: String?,
             task: String,
             amount: Decimal,
             currencyCode: String,
             status: EntryStatus,
             holdDate: Date?) {
            dateKey = LedgerCSV.dayKey(date)
            clientKey = LedgerCSV.normalizedKey(client)
            projectKey = LedgerCSV.normalizedKey(project ?? "")
            taskKey = LedgerCSV.normalizedKey(task)
            self.amount = amount
            self.currencyCode = currencyCode.uppercased()
            self.status = status
            holdDateKey = holdDate.map(LedgerCSV.dayKey) ?? ""
        }
    }

    struct Issue: Identifiable, Hashable {
        enum Kind: Hashable {
            case malformedDocument
            case missingColumn
            case invalidValue
        }

        let rowNumber: Int?
        let message: String
        let kind: Kind

        var id: String { "\(rowNumber.map(String.init) ?? "document")-\(kind)-\(message)" }
    }

    struct Preview {
        let rows: [ImportedRow]
        let issues: [Issue]
        let duplicateRowNumbers: Set<Int>

        var isReadyToImport: Bool {
            !rows.isEmpty && issues.isEmpty && duplicateRowNumbers.isEmpty
        }
    }

    /// Makes an RFC 4180 document. Every field is escaped, including Russian
    /// text and line breaks, so a spreadsheet never receives a shifted column.
    static func export(_ records: [ExportRecord]) -> Data {
        let lines = [columns] + records.map { record in
            [
                dayKey(record.date),
                record.client,
                record.project ?? "",
                record.task,
                decimalString(record.amount),
                record.currencyCode.uppercased(),
                record.status.rawValue,
                record.holdDate.map(dayKey) ?? "",
            ]
        }
        let document = lines
            .map { $0.map(escaped).joined(separator: ",") }
            .joined(separator: "\r\n")
            .appending("\r\n")
        return Data(document.utf8)
    }

    @MainActor
    static func exportRecord(for entry: Entry) -> ExportRecord {
        ExportRecord(
            date: entry.date,
            client: entry.client?.name ?? "",
            project: entry.project,
            task: entry.task,
            amount: entry.amount,
            currencyCode: entry.currencyCode,
            status: entry.status,
            holdDate: entry.holdUntil
        )
    }

    static func clientKey(_ name: String) -> String {
        normalizedKey(name)
    }

    /// Parses and validates a CSV document before any local rows are created.
    /// `existingKeys` lets the UI flag a collision with the current ledger in
    /// the same preview as duplicates inside the file.
    static func preview(_ data: Data,
                        existingKeys: Set<DuplicateKey> = []) -> Preview {
        guard let document = String(data: data, encoding: .utf8) else {
            return Preview(rows: [], issues: [
                Issue(rowNumber: nil, message: "The file is not valid UTF-8.", kind: .malformedDocument),
            ], duplicateRowNumbers: [])
        }

        switch parseTable(document) {
        case .failure(let error):
            return Preview(rows: [], issues: [
                Issue(rowNumber: nil, message: error.message, kind: .malformedDocument),
            ], duplicateRowNumbers: [])
        case .success(let table):
            return buildPreview(table, existingKeys: existingKeys)
        }
    }

    private static func buildPreview(_ table: [[String]],
                                     existingKeys: Set<DuplicateKey>) -> Preview {
        guard let header = table.first else {
            return Preview(rows: [], issues: [
                Issue(rowNumber: nil, message: "The CSV file is empty.", kind: .malformedDocument),
            ], duplicateRowNumbers: [])
        }

        let normalizedHeader = header.enumerated().reduce(into: [String: Int]()) { result, item in
            result[normalizedColumnName(item.element)] = item.offset
        }
        let missing = columns.filter { normalizedHeader[normalizedColumnName($0)] == nil }
        guard missing.isEmpty else {
            return Preview(rows: [], issues: missing.map {
                Issue(rowNumber: 1, message: "Missing required column: \($0).", kind: .missingColumn)
            }, duplicateRowNumbers: [])
        }

        var rows: [ImportedRow] = []
        var issues: [Issue] = []
        var duplicateRows: Set<Int> = []
        var seen = existingKeys

        for (offset, cells) in table.dropFirst().enumerated() {
            let rowNumber = offset + 2
            guard !cells.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            if cells.count != header.count {
                issues.append(Issue(
                    rowNumber: rowNumber,
                    message: "Expected \(header.count) columns, found \(cells.count).",
                    kind: .invalidValue
                ))
                continue
            }

            func value(_ name: String) -> String {
                guard let index = normalizedHeader[normalizedColumnName(name)], cells.indices.contains(index) else {
                    return ""
                }
                return cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            switch importedRow(
                rowNumber: rowNumber,
                date: value("date"),
                client: value("client"),
                project: value("project"),
                task: value("task"),
                amount: value("amount"),
                currencyCode: value("currency_code"),
                status: value("status"),
                holdDate: value("hold_date")
            ) {
            case .failure(let error):
                issues.append(Issue(rowNumber: rowNumber, message: error.message, kind: .invalidValue))
            case .success(let row):
                if !seen.insert(row.duplicateKey).inserted {
                    duplicateRows.insert(rowNumber)
                }
                rows.append(row)
            }
        }

        return Preview(rows: rows, issues: issues, duplicateRowNumbers: duplicateRows)
    }

    private static func importedRow(rowNumber: Int,
                                    date: String,
                                    client: String,
                                    project: String,
                                    task: String,
                                    amount: String,
                                    currencyCode: String,
                                    status: String,
                                    holdDate: String) -> Result<ImportedRow, ValidationError> {
        guard let parsedDate = parseDay(date) else {
            return .failure(ValidationError("Date must use YYYY-MM-DD."))
        }
        guard !client.isEmpty else { return .failure(ValidationError("Client is required.")) }
        guard !task.isEmpty else { return .failure(ValidationError("Task is required.")) }
        guard let parsedAmount = Decimal(string: amount, locale: posixLocale), parsedAmount > 0 else {
            return .failure(ValidationError("Amount must be a positive number using a decimal point."))
        }
        // Ledger entries and the Supabase wire format are money values, not
        // arbitrary-precision decimals. Reject instead of quietly rounding:
        // an import preview must describe exactly what will be saved and
        // later synchronized.
        guard parsedAmount.rounded(2) == parsedAmount else {
            return .failure(ValidationError("Amount can use at most two decimal places."))
        }
        guard parsedAmount <= Limits.maxAmount else {
            return .failure(ValidationError("Amount must not exceed \(Limits.maxAmount)."))
        }
        let code = currencyCode.uppercased()
        guard supportedCurrencyCodes.contains(code) else {
            return .failure(ValidationError("Currency code must be one of \(supportedCurrencyCodes.sorted().joined(separator: ", "))."))
        }
        guard let parsedStatus = parsedStatus(status) else {
            return .failure(ValidationError("Status must be Paid, In progress, or Canceled."))
        }
        let parsedHoldDate: Date?
        if holdDate.isEmpty {
            parsedHoldDate = nil
        } else if let parsed = parseDay(holdDate) {
            parsedHoldDate = parsed
        } else {
            return .failure(ValidationError("Hold date must use YYYY-MM-DD or be empty."))
        }

        return .success(ImportedRow(
            rowNumber: rowNumber,
            date: parsedDate,
            client: client,
            project: project.isEmpty ? nil : project,
            task: task,
            amount: parsedAmount,
            currencyCode: code,
            status: parsedStatus,
            holdDate: parsedHoldDate
        ))
    }

    private static func parsedStatus(_ rawValue: String) -> EntryStatus? {
        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "") {
        case "paid", "logged": .paid
        case "inprogress", "pending": .inProgress
        case "canceled", "cancelled": .canceled
        default: nil
        }
    }

    private struct ValidationError: Error {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }

    private struct TableParseError: Error {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }

    private static func parseTable(_ document: String) -> Result<[[String]], TableParseError> {
        let normalized = document
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let characters = Array(normalized)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if isQuoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    guard field.isEmpty else {
                        return .failure(TableParseError("A quote must start at the beginning of a field."))
                    }
                    isQuoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }
            index += 1
        }

        guard !isQuoted else { return .failure(TableParseError("A quoted field is not closed.")) }
        if !row.isEmpty || !field.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return .success(rows)
    }

    private static func escaped(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    private static func parseDay(_ text: String) -> Date? {
        guard let date = dayFormatter.date(from: text), dayFormatter.string(from: date) == text else {
            return nil
        }
        return date
    }

    private static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func decimalString(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue
    }

    private static func normalizedColumnName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
