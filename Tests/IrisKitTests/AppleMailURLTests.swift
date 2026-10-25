import XCTest
@testable import IrisKit

final class AppleMailURLTests: XCTestCase {
    func testWrapsTheMessageIDInEncodedAngleBrackets() {
        XCTAssertEqual(AppleMailURL.string(forMessageID: "<abc.123@example.com>"), "message://%3Cabc.123@example.com%3E")
    }

    func testAddsTheAngleBracketsWhenTheyAreMissing() {
        XCTAssertEqual(AppleMailURL.string(forMessageID: "abc@example.com"), "message://%3Cabc@example.com%3E")
    }

    func testIgnoresSpacesAroundTheMessageID() {
        XCTAssertEqual(AppleMailURL.string(forMessageID: " <abc@example.com> "), "message://%3Cabc@example.com%3E")
    }

    /// Characters that RFC 5322 allows in a message ID but that have a meaning in a URL.
    func testEncodesURLCharacters() {
        XCTAssertEqual(
            AppleMailURL.string(forMessageID: "<a+b/c=d$e%f?g#h&i@example.com>"),
            "message://%3Ca%2Bb%2Fc%3Dd%24e%25f%3Fg%23h%26i@example.com%3E"
        )
    }

    func testEncodesNonASCIICharactersAsUTF8() {
        XCTAssertEqual(AppleMailURL.string(forMessageID: "<café@example.com>"), "message://%3Ccaf%C3%A9@example.com%3E")
    }

    func testAnEmptyMessageIDHasNoURL() {
        XCTAssertNil(AppleMailURL.string(forMessageID: ""))
        XCTAssertNil(AppleMailURL.string(forMessageID: " "))
        XCTAssertNil(AppleMailURL.string(forMessageID: "<>"))
    }
}
