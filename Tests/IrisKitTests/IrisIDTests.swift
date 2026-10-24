import Foundation
import XCTest
@testable import IrisKit

final class IrisIDTests: XCTestCase {
    func testDescriptionIsAccountMailboxAndUID() {
        XCTAssertEqual(IrisID(account: "work", mailbox: "INBOX", uid: 4821).description, "work/INBOX/4821")
        XCTAssertEqual(
            IrisID(account: "personal", mailbox: "[Gmail]/All Mail", uid: 77).description,
            "personal/[Gmail]/All Mail/77"
        )
    }

    func testParsingSplitsAtTheFirstAndLastSlash() throws {
        XCTAssertEqual(
            try IrisID(parsing: "work/INBOX/4821"),
            IrisID(account: "work", mailbox: "INBOX", uid: 4821)
        )
        XCTAssertEqual(
            try IrisID(parsing: "personal/[Gmail]/All Mail/77"),
            IrisID(account: "personal", mailbox: "[Gmail]/All Mail", uid: 77)
        )
        XCTAssertEqual(
            try IrisID(parsing: "my_gmail/~peter/mail/台北/日本語/5"),
            IrisID(account: "my_gmail", mailbox: "~peter/mail/台北/日本語", uid: 5)
        )
        XCTAssertEqual(
            try IrisID(parsing: "work/Projects//9"),
            IrisID(account: "work", mailbox: "Projects/", uid: 9),
            "a mailbox name may end in a slash"
        )
    }

    func testAccountAndINBOXHaveOneFormWhateverTheCase() throws {
        let id = IrisID(account: "Work", mailbox: "inbox", uid: 5)
        XCTAssertEqual(id, IrisID(account: "work", mailbox: "INBOX", uid: 5))
        XCTAssertEqual(id.description, "work/INBOX/5")
        XCTAssertEqual(try IrisID(parsing: "WORK/Inbox/5"), id)
        XCTAssertEqual(
            IrisID(account: "work", mailbox: "inbox/Receipts", uid: 5).mailbox, "inbox/Receipts",
            "only INBOX itself ignores case"
        )
        XCTAssertEqual(IrisID(account: "work", mailbox: "Archive", uid: 5).mailbox, "Archive")
    }

    func testParsingGivesBackTheSameIDThatDescriptionPrints() throws {
        let ids = [
            IrisID(account: "work", mailbox: "INBOX", uid: 1),
            IrisID(account: "personal", mailbox: "[Gmail]/Sent Mail", uid: UInt32.max),
            IrisID(account: "zoho", mailbox: "R&D", uid: 300),
        ]
        for id in ids {
            XCTAssertEqual(try IrisID(parsing: id.description), id)
        }
    }

    func testParsingRejectsTextThatIsNotAnID() {
        let invalid = [
            "", "4821", "work/4821", "INBOX/4821", "/INBOX/4821", "work//4821", "work/INBOX/",
            "work/INBOX/abc", "work/INBOX/+5", "work/INBOX/-5", "work/INBOX/4821 ", "work/INBOX/４８",
            "work/INBOX/4294967296",
        ]
        for text in invalid {
            XCTAssertThrowsError(try IrisID(parsing: text), "\"\(text)\"") { error in
                XCTAssertEqual(error as? IrisError, .invalidMessageID(text))
            }
        }
    }

    func testJSONIsOneString() throws {
        let id = IrisID(account: "work", mailbox: "[Gmail]/All Mail", uid: 42)
        XCTAssertEqual(try OutputFormatter.json(id, pretty: false), #""work/[Gmail]/All Mail/42""#)
    }
}
