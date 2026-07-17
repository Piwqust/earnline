import Foundation

/// Connection values are injected by the signed build's Info.plist settings,
/// not committed as source. The client only ever needs a publishable key; a
/// service-role key must never appear in an app target.
enum SupabaseProjectDefaults {
    struct ProjectConfig {
        let url: String
        let publishableKey: String
    }

    static let production = ProjectConfig(
        url: value(for: "EarnlineSupabaseProductionURL"),
        publishableKey: value(for: "EarnlineSupabaseProductionPublishableKey")
    )

    /// Test stays local-only; these keys are optional and are never used for
    /// sync. Keeping the slots supports local development without shipping a
    /// project identifier.
    static let test = ProjectConfig(
        url: value(for: "EarnlineSupabaseTestURL"),
        publishableKey: value(for: "EarnlineSupabaseTestPublishableKey")
    )

    private static func value(for key: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.hasPrefix("$(") else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
