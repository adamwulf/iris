import Foundation
import XCTest
@testable import IrisKit

final class MailErrorTests: XCTestCase {
    func testLoginFailureNamesTheKeysAndExplainsAppPasswords() throws {
        let error = IrisError.loginFailed(
            account: "my_gmail", username: "me@gmail.com", host: "imap.gmail.com", reason: "NO [AUTHENTICATIONFAILED] Invalid credentials"
        )
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(message.contains("imap.gmail.com"))
        XCTAssertTrue(message.contains("me@gmail.com"))
        XCTAssertTrue(message.contains("[AUTHENTICATIONFAILED] Invalid credentials"))
        XCTAssertTrue(message.contains("IRIS_MY_GMAIL_IMAP_USERNAME"))
        XCTAssertTrue(message.contains("IRIS_MY_GMAIL_IMAP_PASSWORD"))
        XCTAssertTrue(message.contains("app-specific password"))
        XCTAssertTrue(message.contains("Gmail and iCloud"))
        XCTAssertTrue(message.contains("Zoho needs one when two-factor authentication is on"))
        XCTAssertTrue(message.contains("Zoho also needs IMAP turned on"))
    }

    func testConnectionFailureNamesHostPortAndKeys() throws {
        let error = IrisError.connectionFailed(account: "work", host: "imap.example.com", port: 143, reason: "timed out")
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(message.contains("imap.example.com:143"))
        XCTAssertTrue(message.contains("IRIS_WORK_IMAP_HOST"))
        XCTAssertTrue(message.contains("IRIS_WORK_IMAP_PORT"))
        XCTAssertTrue(message.contains("993"))
    }

    func testUnknownMailboxPointsToTheMailboxesCommandForThatAccount() throws {
        let error = IrisError.unknownMailbox(account: "personal", name: "Nope", reason: "NO no such mailbox")
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertEqual(
            message,
            "The server could not open the mailbox \"Nope\" (account \"personal\"): NO no such mailbox. "
                + "Run `iris mailboxes --account personal` to see the mailbox names."
        )
    }

    func testUnknownUIDPointsToTheListCommandForThatAccountAndMailbox() throws {
        let inbox = try XCTUnwrap(IrisError.unknownUID(account: "work", uid: 999, mailbox: "INBOX").errorDescription)
        XCTAssertEqual(
            inbox,
            "There is no message with UID 999 in \"INBOX\" (account \"work\"). "
                + "Run `iris list --account work` to see the UIDs."
        )
        let sent = try XCTUnwrap(IrisError.unknownUID(account: "work", uid: 5, mailbox: "Sent Items").errorDescription)
        XCTAssertTrue(sent.contains("`iris list --account work --mailbox 'Sent Items'`"))
    }

    func testServerErrorPointsToTheCheckCommandForThatAccount() throws {
        let error = IrisError.serverError(account: "my_gmail", command: "LIST", reason: "NO [UNAVAILABLE] try later")
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertEqual(
            message,
            "The server answered LIST with an error (account \"my_gmail\"): NO [UNAVAILABLE] try later. "
                + "Run `iris check --account my_gmail` to test the account settings."
        )
    }

    func testPageAndLimitErrorsGiveTheValue() {
        XCTAssertEqual(
            IrisError.invalidPage(0).errorDescription,
            "The page number must be 1 or more, not 0. Page 1 has the newest messages."
        )
        XCTAssertEqual(IrisError.invalidLimit(-2).errorDescription, "The limit must be 1 or more, not -2.")
    }

    func testDownloadTimeoutExplainsTheSwiftMailLimit() throws {
        let message = try XCTUnwrap(IrisError.messageDownloadTimedOut(uid: 42, seconds: 10).errorDescription)
        XCTAssertTrue(message.contains("UID 42"))
        XCTAssertTrue(message.contains("10 seconds"))
        XCTAssertTrue(message.contains("large"))
        XCTAssertTrue(message.contains("known limit of SwiftMail"))
    }

    func testServerTimeoutAdvisesRetryingAndASmallerLimitNotTheHostAndPort() throws {
        let message = try XCTUnwrap(IrisError.serverTimedOut(account: "work", command: "FETCH").errorDescription)
        XCTAssertTrue(message.contains("did not answer FETCH in time"))
        XCTAssertTrue(message.contains("\"work\""))
        XCTAssertTrue(message.contains("Try again"))
        XCTAssertTrue(message.contains("smaller --limit"))
        XCTAssertFalse(message.contains("IRIS_WORK_IMAP_HOST"))
        XCTAssertFalse(message.contains("IRIS_WORK_IMAP_PORT"))
    }

    func testRedactingRemovesEveryCopyOfTheSecret() {
        XCTAssertEqual(
            SwiftMailClient.redacting("hunter2", in: "LOGIN me hunter2 failed: hunter2"),
            "LOGIN me <password> failed: <password>"
        )
        XCTAssertEqual(SwiftMailClient.redacting("", in: "NO login failed"), "NO login failed")
    }
}
