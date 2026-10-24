import XCTest
@testable import IrisKit

final class BodyCleanupTests: XCTestCase {
    func testLineEndingsBecomeLineFeeds() {
        XCTAssertEqual(BodyCleanup.clean("a\r\nb\rc\nd"), "a\nb\nc\nd")
    }

    func testTrailingWhitespaceIsRemoved() {
        XCTAssertEqual(BodyCleanup.clean("one \ntwo\t\n> \n\u{00A0}\nthree"), "one\ntwo\n>\n\nthree")
    }

    func testHardBreakIsKeptOnlyBeforeAnotherLineOfText() {
        XCTAssertEqual(
            BodyCleanup.clean("line one   \nline two  \n  \nlast  "),
            "line one  \nline two\n\nlast"
        )
    }

    func testSignatureSeparatorKeepsItsSpace() {
        XCTAssertEqual(BodyCleanup.clean("Thanks\n\n-- \nAdam"), "Thanks\n\n-- \nAdam")
    }

    func testRunsOfBlankLinesAreCutToOne() {
        XCTAssertEqual(BodyCleanup.clean("a\n\nb\n\n\nc\n \n\n\t\n\n\nd"), "a\n\nb\n\nc\n\nd")
    }

    func testBlankLinesAtTheStartAndEndAreDropped() {
        XCTAssertEqual(BodyCleanup.clean("\n \n  indented\n\n\n"), "  indented")
        XCTAssertEqual(BodyCleanup.clean(" \n\n"), "")
    }
}
