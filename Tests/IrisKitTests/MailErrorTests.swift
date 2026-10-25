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

    func testConnectionLostAdvisesRetryingNotTheHostAndPort() throws {
        let error = IrisError.connectionLost(
            account: "work", command: "FETCH", reason: "Connection closed before command completed"
        )
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertEqual(
            message,
            "The connection to the server broke during FETCH (account \"work\"): "
                + "Connection closed before command completed. "
                + "The network may have dropped, or the server may have closed the connection. Try again."
        )
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

    func testUnknownMessagePointsToTheListCommandForThatAccountAndMailbox() throws {
        let inbox = try XCTUnwrap(
            IrisError.unknownMessage(IrisID(account: "work", mailbox: "INBOX", uid: 999)).errorDescription
        )
        XCTAssertEqual(
            inbox,
            "There is no message \"work/INBOX/999\". Run `iris list --account work` to see the iris IDs."
        )
        let sent = try XCTUnwrap(
            IrisError.unknownMessage(IrisID(account: "work", mailbox: "Sent Items", uid: 5)).errorDescription
        )
        XCTAssertTrue(sent.contains("\"work/Sent Items/5\""))
        XCTAssertTrue(sent.contains("`iris list --account work --mailbox 'Sent Items'`"))
    }

    func testInvalidIrisIDShowsTheFormAndAnExample() {
        XCTAssertEqual(
            IrisError.invalidIrisID("4821").errorDescription,
            "\"4821\" is not an iris ID. An iris ID is <account>/<mailbox>/<UID>, "
                + "for example 'work/INBOX/4821'. Put the iris ID in single quotes: a mailbox name can have spaces "
                + "or [ ], which the shell would change. Run `iris list` to see the iris IDs."
        )
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

    func testSearchFailureAdvisesChangingTheFilterNotTheAccount() throws {
        let error = IrisError.searchFailed(account: "work", reason: "Command failed: BAD Could not parse command")
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertEqual(
            message,
            "The server refused the search for the filter options (account \"work\"): "
                + "Command failed: BAD Could not parse command. "
                + "Some servers refuse --from or --subject text that is not ASCII: try ASCII text. "
                + "Else try again with fewer filter options to find the one that the server refuses."
        )
        XCTAssertFalse(message.contains("iris check"), "the login and the mailbox already worked")
    }

    func testPageAndLimitErrorsGiveTheValue() {
        XCTAssertEqual(
            IrisError.invalidPage(0).errorDescription,
            "The page number must be 1 or more, not 0. Page 1 has the newest messages."
        )
        XCTAssertEqual(IrisError.invalidLimit(-2).errorDescription, "The limit must be 1 or more, not -2.")
    }

    func testDownloadTimeoutExplainsTheSwiftMailLimit() throws {
        let message = try XCTUnwrap(IrisError.messageDownloadTimedOut(seconds: 10).errorDescription)
        XCTAssertTrue(message.contains("did not download in 10 seconds"))
        XCTAssertTrue(message.contains("large"))
        XCTAssertTrue(message.contains("known limit of SwiftMail"))
    }

    func testServerTimeoutAdvisesRetryingNotASmallerLimitOrTheHostAndPort() throws {
        let message = try XCTUnwrap(IrisError.serverTimedOut(account: "work", command: "FETCH").errorDescription)
        XCTAssertTrue(message.contains("did not answer FETCH in time"))
        XCTAssertTrue(message.contains("\"work\""))
        XCTAssertTrue(message.contains("Try again"))
        XCTAssertFalse(message.contains("--limit"), "each FETCH asks for at most 100 messages, whatever the limit")
        XCTAssertFalse(message.contains("IRIS_WORK_IMAP_HOST"))
        XCTAssertFalse(message.contains("IRIS_WORK_IMAP_PORT"))
    }

    func testRedactingRemovesEveryCopyOfEverySecret() {
        XCTAssertEqual(
            Redaction.redacting(["hunter2"], in: "LOGIN me hunter2 failed: hunter2"),
            "LOGIN me <redacted> failed: <redacted>"
        )
        XCTAssertEqual(
            Redaction.redacting(["client-secret", "1//refresh"], in: "refresh_token=1//refresh&client_secret=client-secret"),
            "refresh_token=<redacted>&client_secret=<redacted>"
        )
        XCTAssertEqual(Redaction.redacting(["", "x"], in: "NO login failed"), "NO login failed", "an empty secret is skipped")
    }

    func testRedactingRemovesALongerSecretWholeWhenItContainsAShorterOne() {
        XCTAssertEqual(Redaction.redacting(["abc", "abcdef"], in: "token abcdef"), "token <redacted>")
    }

    // MARK: - Google sign-in

    func testNotSignedInNamesTheKeysAndTheLoginCommand() throws {
        XCTAssertEqual(
            IrisError.googleNotSignedIn(account: "personal").errorDescription,
            "The account \"personal\" signs in with Google (it has IRIS_PERSONAL_GOOGLE_CLIENT_ID), "
                + "but it is not signed in yet: IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN is not set. "
                + "Run `iris auth login --account personal` to sign in."
        )
    }

    func testSignInExpiredExplainsTheSevenDayTestingLimit() throws {
        let message = try XCTUnwrap(IrisError.googleSignInExpired(account: "personal").errorDescription)
        XCTAssertTrue(message.contains("expired or was revoked"), message)
        XCTAssertTrue(message.contains("Testing mode signs you out every 7 days"), message)
        XCTAssertTrue(message.contains("`iris auth login --account personal`"), message)
    }

    func testClientRejectedPointsAtTheClientKeys() throws {
        let message = try XCTUnwrap(
            IrisError.googleClientRejected(account: "personal", reason: "HTTP 401, invalid_client").errorDescription
        )
        XCTAssertTrue(message.contains("HTTP 401, invalid_client"), message)
        XCTAssertTrue(message.contains("IRIS_PERSONAL_GOOGLE_CLIENT_ID"), message)
        XCTAssertTrue(message.contains("IRIS_PERSONAL_GOOGLE_CLIENT_SECRET"), message)
        XCTAssertTrue(message.contains("\"Desktop app\""), message)
    }

    func testTokenFailureAdvisesTheNetworkThenAnotherSignIn() throws {
        let message = try XCTUnwrap(
            IrisError.googleTokenFailed(account: "personal", reason: "HTTP 503").errorDescription
        )
        XCTAssertTrue(message.contains("HTTP 503"), message)
        XCTAssertTrue(message.contains("network"), message)
        XCTAssertTrue(message.contains("`iris auth login --account personal`"), message)
    }

    func testNoRefreshTokenPointsAtTheGooglePermissionsPage() throws {
        let message = try XCTUnwrap(IrisError.googleNoRefreshToken(account: "personal").errorDescription)
        XCTAssertTrue(message.contains("https://myaccount.google.com/permissions"), message)
        XCTAssertTrue(message.contains("`iris auth login --account personal`"), message)
    }

    func testGoogleLoginRefusedPointsAtTheUsernameNotAnAppPassword() throws {
        let message = try XCTUnwrap(IrisError.googleLoginRefused(
            account: "personal", username: "me@gmail.com", host: "imap.gmail.com",
            reason: "NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)"
        ).errorDescription)
        XCTAssertTrue(message.contains("imap.gmail.com refused the Google sign-in for me@gmail.com"), message)
        XCTAssertTrue(message.contains("[AUTHENTICATIONFAILED]"), message)
        XCTAssertTrue(message.contains("IRIS_PERSONAL_IMAP_USERNAME"), message)
        XCTAssertTrue(message.contains("`iris auth login --account personal`"), message)
        XCTAssertFalse(message.contains("app-specific password"), message)
        XCTAssertFalse(message.contains("IMAP_PASSWORD"), message)
    }
}
