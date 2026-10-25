import Foundation
import XCTest
@testable import IrisKit

final class AttachmentIDTests: XCTestCase {
    func testDescriptionJoinsTheSectionNumbersWithDots() {
        XCTAssertEqual(AttachmentID(components: [2]).description, "2")
        XCTAssertEqual(AttachmentID(components: [1, 2]).description, "1.2")
        XCTAssertEqual(AttachmentID(components: [3, 1, 12]).description, "3.1.12")
    }

    func testParsingReadsDotSeparatedNumbers() throws {
        XCTAssertEqual(try AttachmentID(parsing: "2"), AttachmentID(components: [2]))
        XCTAssertEqual(try AttachmentID(parsing: "1.2"), AttachmentID(components: [1, 2]))
        XCTAssertEqual(try AttachmentID(parsing: "10.1.3"), AttachmentID(components: [10, 1, 3]))
        XCTAssertEqual(try AttachmentID(parsing: "4294967295").components, [Int(UInt32.max)])
        XCTAssertEqual(try AttachmentID(parsing: "01.2").description, "1.2", "a leading zero is the same number")
    }

    func testParsingGivesBackTheSameIDThatDescriptionPrints() throws {
        for components in [[1], [2], [1, 2], [2, 1, 3]] {
            let id = AttachmentID(components: components)
            XCTAssertEqual(try AttachmentID(parsing: id.description), id)
        }
    }

    func testParsingRejectsTextThatIsNotAnID() {
        let invalid = [
            "", " ", "0", "1.0", "0.1", ".", "1.", ".1", "1..2", "a", "1.a", "+1", "-1", "1 ", " 1", "1,2", "1/2",
            "２", "4294967296", "1.4294967296",
        ]
        for text in invalid {
            XCTAssertThrowsError(try AttachmentID(parsing: text), "\"\(text)\"") { error in
                XCTAssertEqual(error as? IrisError, .invalidAttachmentID(text))
            }
        }
    }

    func testJSONIsOneString() throws {
        XCTAssertEqual(try OutputFormatter.json(AttachmentID(components: [1, 2]), pretty: false), #""1.2""#)
    }
}
