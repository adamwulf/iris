import XCTest
@testable import IrisKit

final class FlowedTextTests: XCTestCase {
    func testSoftBreaksAreJoinedAndTheSpaceIsKept() {
        XCTAssertEqual(
            FlowedText.unwrap("This is a long \nparagraph that \nwraps.\nNew line.", deleteSpace: false),
            "This is a long paragraph that wraps.\nNew line."
        )
    }

    func testDelSpRemovesTheSpaceBeforeEachSoftBreak() {
        XCTAssertEqual(
            FlowedText.unwrap("Supercalifragi \nlistic and  \nmore.", deleteSpace: true),
            "Supercalifragilistic and more."
        )
    }

    func testQuotedLinesAreJoinedAtTheSameDepth() {
        XCTAssertEqual(
            FlowedText.unwrap("> Quoted text that \n> wraps.\n>> Deeper \n>> quote.\nReply.", deleteSpace: false),
            "> Quoted text that wraps.\n>> Deeper quote.\nReply."
        )
    }

    func testAChangeOfQuoteDepthEndsTheParagraph() {
        XCTAssertEqual(
            FlowedText.unwrap("> Improperly flowed \nNot quoted.", deleteSpace: false),
            "> Improperly flowed \nNot quoted."
        )
    }

    func testSpaceStuffingIsRemoved() {
        XCTAssertEqual(
            FlowedText.unwrap("  indented\n From here\n >not a quote", deleteSpace: false),
            " indented\nFrom here\n>not a quote"
        )
    }

    func testEmptyLinesAndTheSignatureSeparatorEndAParagraph() {
        XCTAssertEqual(
            FlowedText.unwrap("Sloppy \n\nNext \n-- \nAdam", deleteSpace: false),
            "Sloppy \n\nNext \n-- \nAdam"
        )
    }

    func testAFlowedLastLineIsKept() {
        XCTAssertEqual(FlowedText.unwrap("Ends \nflowed ", deleteSpace: true), "Endsflowed")
    }
}
