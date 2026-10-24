import IrisKit
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

    func testCheckTakesTheAccountOption() throws {
        XCTAssertNil(try Check.parse([]).accountOptions.account)
        XCTAssertEqual(try Check.parse(["--account", "work"]).accountOptions.account, "work")
    }

    func testMailboxesDefaultsToTableFormat() throws {
        let command = try Mailboxes.parse([])
        XCTAssertEqual(command.format, .table)
        XCTAssertNil(command.accountOptions.account)
    }

    func testMailboxesParsesFormatAndAccount() throws {
        let command = try Mailboxes.parse(["--format", "jsonl", "-a", "work"])
        XCTAssertEqual(command.format, .jsonl)
        XCTAssertEqual(command.accountOptions.account, "work")
    }

    func testListDefaults() throws {
        let command = try List.parse([])
        XCTAssertEqual(command.mailbox, "INBOX")
        XCTAssertEqual(command.page, 1)
        XCTAssertEqual(command.limit, 25)
        XCTAssertEqual(command.format, .table)
        XCTAssertNil(command.accountOptions.account)
    }

    func testListParsesEveryOption() throws {
        let command = try List.parse([
            "--mailbox", "[Gmail]/All Mail", "--page", "3", "--limit", "10", "--format", "id", "--account", "personal",
        ])
        XCTAssertEqual(command.mailbox, "[Gmail]/All Mail")
        XCTAssertEqual(command.page, 3)
        XCTAssertEqual(command.limit, 10)
        XCTAssertEqual(command.format, .id)
        XCTAssertEqual(command.accountOptions.account, "personal")
    }

    func testListRejectsAPageThatIsNotANumber() {
        XCTAssertThrowsError(try List.parse(["--page", "two"]))
    }

    func testListRejectsAnUnknownFormat() {
        XCTAssertThrowsError(try List.parse(["--format", "csv"]))
    }

    func testShowDefaults() throws {
        let command = try Show.parse(["work/INBOX/42"])
        XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertEqual(command.body, .auto)
        XCTAssertEqual(command.format, .markdown)
    }

    func testShowParsesEveryOption() throws {
        let command = try Show.parse(["personal/[Gmail]/Sent Mail/7", "--body", "text", "--format", "raw"])
        XCTAssertEqual(command.irisID, IrisID(account: "personal", mailbox: "[Gmail]/Sent Mail", uid: 7))
        XCTAssertEqual(command.body, .text)
        XCTAssertEqual(command.format, .raw)
    }

    func testShowNeedsAFullIrisID() {
        XCTAssertThrowsError(try Show.parse([]))
        XCTAssertThrowsError(try Show.parse(["42"]))
        XCTAssertThrowsError(try Show.parse(["INBOX/42"]))
        XCTAssertThrowsError(try Show.parse(["work/INBOX/abc"]))
    }

    func testShowExplainsABadIrisID() {
        XCTAssertThrowsError(try Show.parse(["42"])) { error in
            let message = Show.message(for: error)
            XCTAssertTrue(message.contains("\"42\" is not an iris ID"), message)
            XCTAssertTrue(message.contains("<account>/<mailbox>/<UID>"), message)
        }
    }

    func testShowHasNoAccountOrMailboxOption() {
        // The iris ID names both.
        XCTAssertThrowsError(try Show.parse(["work/INBOX/42", "--account", "work"]))
        XCTAssertThrowsError(try Show.parse(["work/INBOX/42", "--mailbox", "INBOX"]))
    }

    /// ArgumentParser lists an option's values itself, so our help strings no longer list them too.
    func testHelpNoLongerHasTheOldValueLists() {
        let oldPhrases = ["table, json, jsonl, or id", "markdown, json, or raw", "auto (HTML", "text, or html"]
        let helps = [
            Accounts.helpMessage(columns: 1000),
            Mailboxes.helpMessage(columns: 1000),
            List.helpMessage(columns: 1000),
            Show.helpMessage(columns: 1000),
        ]
        for help in helps {
            for phrase in oldPhrases {
                XCTAssertFalse(help.contains(phrase), "\(phrase) in \(help)")
            }
        }
    }
}
