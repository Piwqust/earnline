import Foundation

/// Reads the release-injected public policy URL without ever treating an
/// unresolved Info.plist build-setting placeholder as a valid destination.
enum PrivacyPolicyURL {
    static var current: URL? {
        url(from: Bundle.main.object(forInfoDictionaryKey: "EarnlinePrivacyPolicyURL") as? String)
    }

    static func url(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }
}
