import Foundation

/// Shared date helpers. Compact numeric dates come from a localized template,
/// so the field order and punctuation follow the user's region ("12.07.26" in
/// Berlin, "7/12/26" in New York) instead of a hardcoded `dd.MM.yy`.
enum DateFormat {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("ddMMyy")
        return f
    }()

    static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("LLLL")
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return f
    }()

    /// Weekday-prefixed compact date for the heatmap's tapped-day headline
    /// ("Mon, 12.07.26" / "Mon, 7/12/26" by region).
    static let weekdayDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEEddMMyy")
        return f
    }()

    static func dotted(_ date: Date) -> String { short.string(from: date) }

    static func weekdayAndDate(_ date: Date) -> String { weekdayDate.string(from: date) }

    static func month(_ date: Date) -> String {
        monthName.string(from: date).capitalized
    }

    /// "July 2026" — used where the bare month name would be ambiguous.
    static func monthAndYear(_ date: Date) -> String {
        monthYear.string(from: date).capitalized
    }

    /// First day of the month containing `date` — used as a grouping key.
    static func monthStart(of date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}
