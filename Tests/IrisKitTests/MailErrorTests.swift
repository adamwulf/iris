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
                + "Some servers refuse filter text that is not ASCII: try ASCII text. "
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

    // MARK: - Drafts

    func testDraftBodyErrorsSayHowToGiveTheReply() throws {
        let twice = try XCTUnwrap(IrisError.draftBodyGivenTwice.errorDescription)
        XCTAssertEqual(
            twice,
            "The reply was given twice: as an argument and with -F. "
                + "Give it one way: as an argument, with -F <path>, or on stdin."
        )
        let missing = try XCTUnwrap(IrisError.draftBodyMissing.errorDescription)
        XCTAssertTrue(missing.contains("as an argument"), missing)
        XCTAssertTrue(missing.contains("-F <path> (-F - reads stdin)"), missing)
        XCTAssertTrue(missing.contains("echo 'Thanks!' | iris draft '<iris-id>'"), missing)

        XCTAssertEqual(
            IrisError.draftBodyEmpty(source: "stdin").errorDescription,
            "The reply from stdin is empty. Write the reply in Markdown, "
                + "and give it as an argument, with -F <path>, or on stdin."
        )
        XCTAssertEqual(
            IrisError.draftBodyNotRead(source: "the file \"reply.md\"", reason: "No such file.").errorDescription,
            "Could not read the reply from the file \"reply.md\" (No such file.). "
                + "Check the path, or give the reply as an argument or on stdin."
        )
        XCTAssertEqual(
            IrisError.draftBodyNotUTF8(source: "stdin").errorDescription,
            "The reply from stdin is not UTF-8 text. Save it as UTF-8, or give the reply as an argument."
        )
    }

    func testMissingFromAddressNamesTheKeyAndTheUsername() throws {
        let message = try XCTUnwrap(
            IrisError.draftFromAddressMissing(account: "my_icloud", username: "emily").errorDescription
        )
        XCTAssertTrue(message.contains("account \"my_icloud\" (\"emily\") is not an address"), message)
        XCTAssertTrue(message.contains("Set IRIS_MY_ICLOUD_FROM to your address"), message)
        XCTAssertTrue(message.contains("\"IRIS_MY_ICLOUD_FROM=Your Name <you@example.com>\""), message)
    }

    func testMissingDraftsMailboxPointsToTheMailboxesCommandForThatAccount() {
        XCTAssertEqual(
            IrisError.draftsMailboxNotFound(account: "work").errorDescription,
            "The server has no mailbox marked \\Drafts (account \"work\"), so iris does not know "
                + "where to save the draft. Run `iris mailboxes --account work` to see the mailboxes and their attributes."
        )
    }

    func testDraftTooLargeGivesBothSizesAndHowToShortenIt() {
        XCTAssertEqual(
            IrisError.draftTooLarge(account: "work", size: 2_000_000, limit: 1_000_000).errorDescription,
            "The draft is 2000000 bytes, and the server takes at most 1000000 bytes (account \"work\"). "
                + "Attach fewer or smaller files, shorten the reply, or leave out the quoted message with --no-quote."
        )
    }

    func testDraftMayBeSavedNamesTheMailboxToLookInBeforeTryingAgain() {
        XCTAssertEqual(
            IrisError.draftMayBeSaved(
                account: "personal", mailbox: "[Gmail]/Drafts", reason: "the server did not answer APPEND in time"
            ).errorDescription,
            "Saving the draft did not finish (account \"personal\"): the server did not answer APPEND in time. "
                + "The server may have saved it in \"[Gmail]/Drafts\" anyway: look in it "
                + "(`iris list --account personal --mailbox '[Gmail]/Drafts'`) before you try again."
        )
    }

    func testAttachmentErrorsNameThePathAndSayWhatToDo() {
        XCTAssertEqual(
            IrisError.draftAttachmentNotRead(
                path: "docs/q4.pdf", reason: "The file “q4.pdf” couldn’t be opened because there is no such file."
            ).errorDescription,
            "Could not read the file \"docs/q4.pdf\" to attach it "
                + "(The file “q4.pdf” couldn’t be opened because there is no such file.). "
                + "Check the path (a relative path starts in the current directory) and that you can read the file."
        )
        XCTAssertEqual(
            IrisError.draftAttachmentIsAFolder(path: "docs").errorDescription,
            "\"docs\" is a folder, and --attach takes a file. "
                + "Give --attach once for each file in the folder, or attach a .zip of it."
        )
    }

    /// A refused draft is about its size or the mailbox, not the account settings that `iris check` tests.
    func testDraftRefusedNamesTheMailboxTheReasonAndTheUsualCauses() {
        XCTAssertEqual(
            IrisError.draftRefused(
                account: "work", mailbox: "Drafts", reason: "Command failed: NO [TOOBIG] Message too large"
            ).errorDescription,
            "The server refused to save the draft in \"Drafts\" (account \"work\"): "
                + "Command failed: NO [TOOBIG] Message too large. The usual cause is the draft's size: "
                + "attach fewer or smaller files, or leave out the quoted message with --no-quote. "
                + "A full mailbox is another: make room, then try again."
        )
    }

    func testAReplyThatNamesAFileSaysToRepeatAttachOrUseF() {
        XCTAssertEqual(
            IrisError.draftBodyNamesAFile(path: "b.pdf").errorDescription,
            "The reply is \"b.pdf\", which is the name of a file. Each --attach takes one path, "
                + "so a second path after it (or the second file that a pattern such as *.pdf matched) "
                + "becomes the reply. Give --attach once for each file, as in --attach a.pdf --attach b.pdf, "
                + "and give a reply that is in a file with -F <path>."
        )
    }

    // MARK: - Attachments

    func testNoBytesForAnAttachmentSaysNothingWasSavedAndToTryAgain() {
        XCTAssertEqual(
            IrisError.attachmentNotReceived(
                IrisID(account: "work", mailbox: "INBOX", uid: 150), AttachmentID(components: [2])
            ).errorDescription,
            "The server sent no bytes for attachment 2 of the message \"work/INBOX/150\", which is not empty, "
                + "so iris saved nothing. Try again."
        )
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

    func testNotSignedInNamesTheRefreshTokenKeyAndTheLoginCommand() throws {
        XCTAssertEqual(
            IrisError.googleNotSignedIn(account: "personal").errorDescription,
            "IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN is not set. Run `iris auth login --account personal` to sign in."
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
