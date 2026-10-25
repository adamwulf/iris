import Foundation

/// A day with no time and no time zone, such as 2026-10-24. IMAP SEARCH
/// compares days, not times (SINCE and BEFORE, RFC 3501 section 6.4.4).
public struct CalendarDay: Sendable, Equatable, CustomStringConvertible {
    /// The years that SwiftMail can send. Its search code stops the program
    /// for other years (`IMAPCalendarDay` holds only 1900 to 2500).
    static let years = 1900...2500

    /// The calendar that gives `start` its day. Pass the same one to SwiftMail,
    /// so the day it sends is this day in every time zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    public let year: Int
    public let month: Int
    public let day: Int
    /// Midnight at the start of the day in `calendar`.
    let start: Date

    /// Parses `YYYY-MM-DD`, for example `2026-10-24`. Throws `invalidDate` for
    /// other text, for a day that does not exist (2026-02-30), and for a year
    /// outside 1900 to 2500.
    public init(parsing text: String) throws {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.utf8.count) == [4, 2, 2],
              parts.allSatisfy({ $0.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              Self.years.contains(year),
              let start = Self.calendar.date(from: DateComponents(year: year, month: month, day: day))
        else {
            throw IrisError.invalidDate(text)
        }
        // date(from:) moves a day that does not exist to a later one (February 30
        // becomes March 2), so the day must come back unchanged.
        let back = Self.calendar.dateComponents([.year, .month, .day], from: start)
        guard back.year == year, back.month == month, back.day == day else {
            throw IrisError.invalidDate(text)
        }
        self.year = year
        self.month = month
        self.day = day
        self.start = start
    }

    /// `2026-10-24`, the form that `init(parsing:)` reads.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
