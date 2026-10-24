import Foundation
import XCTest
@testable import IrisKit

final class HeaderDateTests: XCTestCase {
    private let expected = ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z")

    private func raw(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    func testTrailingCDTCommentIsIgnored() {
        XCTAssertEqual(HeaderDate.date(inRawMessage: raw("Subject: x\nDate: Sat, 24 Oct 2026 13:42:00 -0500 (CDT)\n\nBody")), expected)
    }

    func testTrailingUTCCommentIsIgnored() {
        XCTAssertEqual(HeaderDate.date(inRawMessage: raw("DATE: Sat, 24 Oct 2026 18:42:00 +0000 (UTC)\n\nBody")), expected)
    }

    func testDateWithoutAComment() {
        XCTAssertEqual(HeaderDate.date(inRawMessage: raw("Date: Sat, 24 Oct 2026 13:42:00 -0500\n\nBody")), expected)
    }

    func testFoldedHeaderIsUnfolded() {
        XCTAssertEqual(HeaderDate.date(inRawMessage: raw("Date: Sat, 24 Oct 2026\n\t13:42:00 -0500\n (CDT)\nTo: a@example.com\n\nBody")), expected)
    }

    func testGarbageGivesNil() {
        XCTAssertNil(HeaderDate.date(inRawMessage: raw("Date: next Tuesday (CDT)\n\nBody")))
    }

    func testOnlyTheTopLevelHeaderBlockIsRead() {
        XCTAssertNil(HeaderDate.date(inRawMessage: raw("Subject: x\n\nDate: Sat, 24 Oct 2026 13:42:00 -0500")))
    }

    func testWeekdayAndSecondsAreOptional() {
        XCTAssertEqual(HeaderDate.parse("24 Oct 2026 13:42 -0500"), expected)
        XCTAssertEqual(HeaderDate.parse("Sat, 24 Oct 2026 13:42 -0500"), expected)
        XCTAssertEqual(HeaderDate.parse("4 Oct 2026 20:42:00 +0200"), ISO8601DateFormatter().date(from: "2026-10-04T18:42:00Z"))
    }
}
