import Foundation

/// Hard limits to keep values sane and layouts inside their borders.
enum Limits {
    static let maxAmount: Decimal = 1_000_000_000
    static let maxAmountDigits = 12
    static let maxProjectLength = 40
    static let maxTaskLength = 140
    static let maxClientNameLength = 24
    static let maxHeadingLength = 40
    static let supportedCurrencyCodes = ["USD", "EUR", "GBP", "RUB", "UAH"]
}

/// Supabase publishable/anon keys are safe for a client app; secret and
/// service-role keys are server credentials and must fail closed everywhere.
/// Keep this check shared by the Debug connection editor, runtime setup, and
/// release configuration tests so those paths cannot drift apart.
enum SupabaseKeyValidation {
    static func looksLikeSecretKey(_ rawKey: String) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.lowercased().hasPrefix("sb_secret_") { return true }

        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payloadData = base64URLDecoded(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let role = payload["role"] as? String else {
            return key.localizedCaseInsensitiveContains("service_role")
        }
        return role.caseInsensitiveCompare("service_role") == .orderedSame
    }

    private static func base64URLDecoded(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

enum ClientNameValidation: Equatable {
    case valid(String)
    case empty
    case duplicate

    var message: String? {
        switch self {
        case .valid:
            return nil
        case .empty:
            return String(localized: "Enter a client name.")
        case .duplicate:
            return String(localized: "A client with this name already exists.")
        }
    }

    var validName: String? {
        if case .valid(let name) = self { return name }
        return nil
    }
}

enum Validation {
    /// Clamp an amount into (0, maxAmount] and snap to cents. Local rows must
    /// match the `numeric(14, 2)` wire contract; extra fraction digits used to
    /// display one total until the next sync pull rewrote them.
    static func clampAmount(_ value: Decimal) -> Decimal {
        if value < 0 { return 0 }
        return min(value, Limits.maxAmount).rounded(2)
    }

    /// Keep only digits and a single decimal separator (capped digits) as the user types.
    static func sanitizeAmountInput(_ raw: String) -> String {
        var out = ""
        var seenSeparator = false
        var digitCount = 0
        for ch in raw {
            if ch.isNumber {
                guard digitCount < Limits.maxAmountDigits else { continue }
                out.append(ch); digitCount += 1
            } else if ch == "." || ch == "," {
                guard !seenSeparator else { continue }
                seenSeparator = true
                out.append(".")
            }
        }
        return out
    }

    static func trimmed(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= max ? t : String(t.prefix(max))
    }

    /// Cap a string's length while editing (no trim, so trailing spaces are allowed mid-type).
    static func capped(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max))
    }

    static func validateClientName(_ raw: String, existingNames: [String]) -> ClientNameValidation {
        let name = trimmed(raw, max: Limits.maxClientNameLength)
        guard !name.isEmpty else { return .empty }
        let key = clientNameKey(name)
        let duplicate = existingNames.contains { clientNameKey($0) == key }
        return duplicate ? .duplicate : .valid(name)
    }

    private static func clientNameKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

/// Wire values are untrusted even after RLS has selected the correct workspace.
/// Keep these checks aligned with the local editors and database constraints so
/// one malformed cloud row cannot poison SwiftData or make a later push fail.
enum SyncValidation {
    static func isValidClient(name: String, colorHex: String) -> Bool {
        isCanonicalNonEmpty(name, maximum: Limits.maxClientNameLength)
            && colorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }

    static func isValidEntry(amount: Decimal,
                             currencyCode: String,
                             project: String?,
                             task: String,
                             status: String) -> Bool {
        amount > 0
            && amount <= Limits.maxAmount
            && Limits.supportedCurrencyCodes.contains(currencyCode)
            && (project.map(isCanonicalOptionalProject) ?? true)
            && isCanonicalNonEmpty(task, maximum: Limits.maxTaskLength)
            && EntryStatus.allCases.contains { $0.rawValue == status }
    }

    static func isValidHeading(title: String) -> Bool {
        isCanonicalNonEmpty(title, maximum: Limits.maxHeadingLength)
    }

    static func isCanonicalOptionalProject(_ project: String) -> Bool {
        project.count <= Limits.maxProjectLength
            && project == project.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isCanonicalNonEmpty(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximum
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
