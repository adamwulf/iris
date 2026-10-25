import XCTest
@testable import IrisKit

final class FileLogPolicyTests: XCTestCase {
    func testReadOnlyInvocationsNeverWriteFiles() {
        for arguments in [["ro"], ["ro", "show", "work/INBOX/1"], ["--", "ro", "accounts"]] {
            XCTAssertFalse(FileLogPolicy.writesFiles(arguments: arguments))
        }
        XCTAssertTrue(FileLogPolicy.writesFiles(arguments: ["list", "--subject", "ro"]))
    }

    func testErrorsDiscardAllAssociatedDataIncludingServerAndMailContent() {
        let sensitive = "private-account https://private.example key=secret-token sender@example.com subject draft-body"
        let cases: [(IrisError, String)] = [
            (.invalidSetting(key: sensitive, reason: sensitive), "invalid_setting"),
            (.missingSetting(key: sensitive), "missing_setting"),
            (.loginFailed(account: sensitive, username: sensitive, host: sensitive, reason: sensitive), "login_failed"),
            (.serverError(account: sensitive, command: sensitive, reason: sensitive), "server_error"),
            (.searchFailed(account: sensitive, reason: sensitive), "search_failed"),
            (.unknownMailbox(account: sensitive, name: sensitive, reason: sensitive), "unknown_mailbox"),
            (.googleTokenFailed(account: sensitive, reason: sensitive), "google_token_failed"),
            (.googleSignInFailed(account: sensitive, reason: sensitive), "google_sign_in_failed"),
            (.messageNotParsed(reason: sensitive), "message_not_parsed"),
            (.htmlNotConverted(reason: sensitive, hasTextPart: true), "html_not_converted"),
            (.draftRefused(account: sensitive, mailbox: sensitive, reason: sensitive), "draft_refused"),
            (.draftNotPreserved(reason: sensitive), "draft_not_preserved"),
            (.draftRecipientInvalid(option: sensitive, value: sensitive), "draft_recipient_invalid"),
            (.draftBodyNotRead(source: sensitive, reason: sensitive), "draft_body_not_read"),
            (.attachmentNotSaved(path: sensitive, reason: sensitive), "attachment_not_saved"),
            (.invalidIrisID(sensitive), "invalid_iris_id"),
        ]
        for (error, code) in cases {
            XCTAssertEqual(FileLogPolicy.failureCode(error), code)
        }
    }

    func testUnknownErrorsAreNeverRendered() {
        struct UnprintableError: Error, CustomStringConvertible, LocalizedError {
            var description: String { XCTFail("must not render errors for disk"); return "private" }
            var errorDescription: String? { XCTFail("must not localize errors for disk"); return "private" }
        }
        XCTAssertEqual(FileLogPolicy.failureCode(UnprintableError()), "command_failed")
    }

    func testInteractiveMessagesNeverReachPersistentSink() {
        let console = LogRecorder()
        let file = LogRecorder()
        let previousHandler = IrisLog.handler
        let previousFileHandler = IrisLog.fileHandler
        defer {
            IrisLog.handler = previousHandler
            IrisLog.fileHandler = previousFileHandler
        }
        IrisLog.handler = console.record
        IrisLog.fileHandler = { file.record($0.rawValue) }
        let sensitive = "private URL, token, email subject and body"
        IrisLog.log(sensitive)
        IrisLog.log(sensitive, fileEvent: .threadSearchFallback)
        XCTAssertEqual(console.lines, [sensitive, sensitive])
        XCTAssertEqual(file.lines, ["thread_search_fallback"])
    }
}
