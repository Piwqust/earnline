import Foundation

/// Shared date helpers. earn›line shows dates as `DD.MM.YY` (per Figma).
enum DateFormat {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM.yy"
        return f
    }()

    static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static func dotted(_ date: Date) -> String { short.string(from: date) }

    static func month(_ date: Date) -> String {
        monthName.string(from: date).capitalized
    }

    /// First day of the month containing `date` — used as a grouping key.
    static func monthStart(of date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}
