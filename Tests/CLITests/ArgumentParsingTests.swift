import XCTest
@testable import iris

final class ArgumentParsingTests: XCTestCase {
    func testAccountsDefaultsToTableFormat() throws {
        XCTAssertEqual(try Accounts.parse([]).format, .table)
    }

    func testAccountsParsesFormat() throws {
        XCTAssertEqual(try Accounts.parse(["--format", "json"]).format, .json)
    }

    func testAccountOptionsParseShortAndLongNames() throws {
        XCTAssertEqual(try AccountOptions.parse(["--account", "work"]).account, "work")
        XCTAssertEqual(try AccountOptions.parse(["-a", "work"]).account, "work")
        XCTAssertNil(try AccountOptions.parse([]).account)
    }
}
