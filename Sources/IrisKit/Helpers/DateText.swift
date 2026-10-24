import Foundation

/// How iris prints a date for people to read: `yyyy-MM-dd HH:mm`, to the minute.
/// `iris list` and `iris show` both use it, so their dates look the same.
enum DateText {
    /// `2026-10-24 13:42` in `timeZone`. With `showingZone`, the short name of
    /// the zone follows: `2026-10-24 13:42 CDT`.
    static func string(from date: Date, timeZone: TimeZone, showingZone: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = showingZone ? "yyyy-MM-dd HH:mm zzz" : "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
