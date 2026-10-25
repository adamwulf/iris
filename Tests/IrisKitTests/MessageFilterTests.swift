import Foundation
import XCTest
@testable import IrisKit

final class MessageFilterTests: XCTestCase {
    // MARK: - CalendarDay

    func testDayParsesYYYYMMDD() throws {
        let day = try CalendarDay(parsing: "2026-10-04")
        XCTAssertEqual(day.year, 2026)
        XCTAssertEqual(day.month, 10)
        XCTAssertEqual(day.day, 4)
        XCTAssertEqual(day.description, "2026-10-04")
    }

    func testDayStartsAtMidnightInItsCalendarInEveryTimeZone() throws {
        let day = try CalendarDay(parsing: "2026-03-08")
        XCTAssertEqual(day.start, Date(timeIntervalSince1970: 1_772_928_000), "2026-03-08 00:00 UTC")
        let back = CalendarDay.calendar.dateComponents([.year, .month, .day, .hour], from: day.start)
        XCTAssertEqual([back.year, back.month, back.day, back.hour], [2026, 3, 8, 0])
    }

    func testDayAcceptsLeapDaysAndTheEndsOfTheYearRange() throws {
        XCTAssertEqual(try CalendarDay(parsing: "2024-02-29").description, "2024-02-29")
        XCTAssertEqual(try CalendarDay(parsing: "1900-01-01").description, "1900-01-01")
        XCTAssertEqual(try CalendarDay(parsing: "2500-12-31").description, "2500-12-31")
    }

    func testDayRejectsOtherTextAndDaysThatDoNotExist() {
        let bad = [
            "", "2026", "2026-10", "2026-1-5", "26-10-04", "2026-10-04-01", "2026/10/04", "20261004",
            "2026-10-4", " 2026-10-04", "2026-10-04 ", "+026-10-04", "2026-١٠-04", "2026-oc-04",
            "2026-02-29", "2026-02-30", "2026-04-31", "2026-13-01", "2026-00-10", "2026-10-00", "2026-10-32",
            "1899-12-31", "2501-01-01", "0000-01-01",
        ]
        for text in bad {
            XCTAssertThrowsError(try CalendarDay(parsing: text), "\"\(text)\"") { error in
                XCTAssertEqual(error as? IrisError, .invalidDate(text))
            }
        }
    }

    func testInvalidDateErrorShowsTheFormAndTheYears() {
        XCTAssertEqual(
            IrisError.invalidDate("yesterday").errorDescription,
            "\"yesterday\" is not a date. Type a day as YYYY-MM-DD, for example 2026-10-24, from the year 1900 to 2500."
        )
    }

    // MARK: - MessageFilter

    func testFilterIsEmptyOnlyWithNoCondition() throws {
        XCTAssertTrue(MessageFilter().isEmpty)
        let day = try CalendarDay(parsing: "2026-10-01")
        let filters = [
            MessageFilter(unread: true),
            MessageFilter(flagged: true),
            MessageFilter(from: "jane"),
            MessageFilter(from: ""),
            MessageFilter(to: "bob"),
            MessageFilter(subject: "Hi"),
            MessageFilter(search: "invoice"),
            MessageFilter(since: day),
            MessageFilter(before: day),
        ]
        for filter in filters {
            XCTAssertFalse(filter.isEmpty, "\(filter)")
        }
    }

    func testFilterOptionsLeaveOutConditionsThatAreNotSet() throws {
        XCTAssertEqual(MessageFilter().options, [])
        XCTAssertEqual(MessageFilter(flagged: true).options, ["--flagged"])
        XCTAssertEqual(
            MessageFilter(subject: "Q4 plan", before: try CalendarDay(parsing: "2026-11-01")).options,
            ["--subject", "'Q4 plan'", "--before", "2026-11-01"]
        )
        XCTAssertEqual(MessageFilter(search: "invoice 42").options, ["--search", "'invoice 42'"])
        XCTAssertEqual(MessageFilter(to: "bob@example.com").options, ["--to", "bob@example.com"])
    }
}
