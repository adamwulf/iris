import XCTest
@testable import IrisKit

final class MailAddressTests: XCTestCase {
    private func name(_ name: String?) -> String? {
        MailAddress(name: name, address: "jane@example.com").name
    }

    /// Zoho sends these in the ENVELOPE, quotes included.
    func testAFullyQuotedNameLosesItsQuotes() {
        XCTAssertEqual(name(#""Gonzalez-Schulenberg, Liana""#), "Gonzalez-Schulenberg, Liana")
        XCTAssertEqual(name(#""tmccarthy@godaddy.com""#), "tmccarthy@godaddy.com")
    }

    func testAQuotedNameUnescapesItsQuotedPairs() {
        XCTAssertEqual(name(#""Jane \"JD\" Doe""#), #"Jane "JD" Doe"#)
        XCTAssertEqual(name(#""Back\\slash""#), #"Back\slash"#)
    }

    func testQuotesInsideANameStay() {
        XCTAssertEqual(name(#"Robert "Bob" Smith"#), #"Robert "Bob" Smith"#)
        XCTAssertEqual(name(#""Bob" Smith "Jr""#), #""Bob" Smith "Jr""#)
    }

    /// The last quote is escaped, so the quoted-string never ends.
    func testAnUnclosedQuotedNameStays() {
        XCTAssertEqual(name(#""Doe\""#), #""Doe\""#)
        XCTAssertEqual(name("\""), "\"")
    }

    func testAPlainNameStays() {
        XCTAssertEqual(name("Jane Doe"), "Jane Doe")
    }

    func testNoNameStaysNil() {
        XCTAssertNil(name(nil))
    }

    /// `list --format json` then leaves out the name, as `show` does.
    func testAnEmptyQuotedNameIsNilAndShowsTheAddress() {
        let address = MailAddress(name: "\"\"", address: "jane@example.com")
        XCTAssertNil(address.name)
        XCTAssertEqual(address.displayName, "jane@example.com")
    }
}
