import Foundation
import SwiftMail
import XCTest
@testable import IrisKit

/// The parts of `SwiftMailClient` that need no server: the TLS choice, the
/// error mapping, and the mailbox conversion.
final class SwiftMailClientTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com", password: "secret"
    )

    private func irisError(_ error: any Error, _ command: SwiftMailClient.Command) -> IrisError {
        SwiftMailClient.irisError(for: error, command: command, account: account)
    }

    // MARK: - Transport security

    func testPort143UpgradesWithSTARTTLS() {
        XCTAssertEqual(SwiftMailClient.transportSecurity(forPort: 143), .startTLS)
    }

    func testEveryOtherPortUsesTLSFromTheFirstByte() {
        for port in [993, 1993, 144, 8143] {
            XCTAssertEqual(SwiftMailClient.transportSecurity(forPort: port), .implicitTLS, "port \(port)")
        }
    }

    // MARK: - Error mapping

    func testIrisErrorsPassThrough() {
        let error = IrisError.invalidLimit(0)
        XCTAssertEqual(irisError(error, .fetchEnvelopes), error)
    }

    func testLoginAndAuthFailuresBecomeLoginFailedWithoutThePassword() {
        let expected = IrisError.loginFailed(
            account: "work", username: "me@example.com", host: "imap.example.com", reason: "NO bad <password>"
        )
        XCTAssertEqual(irisError(IMAPError.loginFailed("NO bad secret"), .login), expected)
        XCTAssertEqual(irisError(IMAPError.authFailed("NO bad secret"), .login), expected)
    }

    func testSelectFailedOnExamineBecomesUnknownMailbox() {
        XCTAssertEqual(
            irisError(IMAPError.selectFailed("NO [NONEXISTENT] secret"), .examine(mailbox: "Nope")),
            .unknownMailbox(name: "Nope", reason: "NO [NONEXISTENT] <password>")
        )
    }

    func testTimeoutOnARawMessageBecomesMessageDownloadTimedOut() {
        XCTAssertEqual(
            irisError(IMAPError.timeout, .fetchRawMessage(uid: 42)),
            .messageDownloadTimedOut(uid: 42, seconds: SwiftMailClient.rawMessageTimeoutSeconds)
        )
    }

    func testTimeoutOnLoginBecomesConnectionFailed() {
        XCTAssertEqual(
            irisError(IMAPError.timeout, .login),
            .connectionFailed(
                account: "work", host: "imap.example.com", port: 993, reason: "the server did not answer LOGIN in time"
            )
        )
    }

    func testConnectionAndGreetingFailuresBecomeConnectionFailedWithoutThePassword() {
        for error in [IMAPError.connectionFailed("reset secret"), IMAPError.greetingFailed("reset secret")] {
            XCTAssertEqual(
                irisError(error, .capability),
                .connectionFailed(account: "work", host: "imap.example.com", port: 993, reason: "reset <password>")
            )
        }
    }

    func testOtherIMAPErrorsBecomeServerErrorsNamingTheCommand() {
        XCTAssertEqual(
            irisError(IMAPError.commandFailed("NO [UNAVAILABLE] secret"), .list),
            .serverError(command: "LIST", reason: "Command failed: NO [UNAVAILABLE] <password>")
        )
        XCTAssertEqual(
            irisError(IMAPError.selectFailed("NO"), .fetchEnvelopes),
            .serverError(command: "FETCH", reason: "Select mailbox failed: NO"),
            "selectFailed means an unknown mailbox only for EXAMINE"
        )
    }

    func testOtherErrorsAreNetworkFailuresAndBecomeConnectionFailed() {
        struct TLSFailure: Error, CustomStringConvertible {
            var description: String { "handshake failed for secret" }
        }
        XCTAssertEqual(
            irisError(TLSFailure(), .login),
            .connectionFailed(
                account: "work", host: "imap.example.com", port: 993, reason: "handshake failed for <password>"
            )
        )
    }

    func testCommandNames() {
        XCTAssertEqual(SwiftMailClient.Command.login.name, "LOGIN")
        XCTAssertEqual(SwiftMailClient.Command.capability.name, "CAPABILITY")
        XCTAssertEqual(SwiftMailClient.Command.list.name, "LIST")
        XCTAssertEqual(SwiftMailClient.Command.examine(mailbox: "INBOX").name, "EXAMINE")
        XCTAssertEqual(SwiftMailClient.Command.fetchEnvelopes.name, "FETCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchRawMessage(uid: 1).name, "FETCH")
    }

    // MARK: - Mailboxes

    func testMailboxInfoKeepsOnlyTheSpecialUseAttributesInNameOrder() {
        let info = Mailbox.Info(
            name: "[Gmail]/Sent Mail",
            attributes: [.sent, .hasNoChildren, .inbox, .all, .marked],
            hierarchyDelimiter: "/"
        )
        XCTAssertEqual(
            MailboxInfo(swiftMail: info),
            MailboxInfo(name: "[Gmail]/Sent Mail", attributes: [#"\All"#, #"\Sent"#])
        )
    }

    func testMailboxInfoMapsEverySpecialUseAttribute() {
        let info = Mailbox.Info(
            name: "Everything",
            attributes: [.all, .archive, .drafts, .flagged, .important, .junk, .sent, .trash],
            hierarchyDelimiter: nil
        )
        XCTAssertEqual(
            MailboxInfo(swiftMail: info).attributes,
            [#"\All"#, #"\Archive"#, #"\Drafts"#, #"\Flagged"#, #"\Important"#, #"\Junk"#, #"\Sent"#, #"\Trash"#]
        )
    }
}
