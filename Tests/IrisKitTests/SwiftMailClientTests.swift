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
            .unknownMailbox(account: "work", name: "Nope", reason: "NO [NONEXISTENT] <password>")
        )
        XCTAssertEqual(
            irisError(IMAPError.selectFailed("NO"), .examine(mailbox: "[Gmail]/Entw&APw-rfe")),
            .unknownMailbox(account: "work", name: "[Gmail]/Entw&APw-rfe", reason: "NO"),
            "the error holds the wire name; MailReader puts back the name the user typed"
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

    func testTimeoutAfterLoginBecomesServerTimedOut() {
        let commands: [SwiftMailClient.Command] = [.capability, .list, .examine(mailbox: "INBOX"), .fetchEnvelopes]
        for command in commands {
            XCTAssertEqual(
                irisError(IMAPError.timeout, command),
                .serverTimedOut(account: "work", command: command.name),
                "\(command)"
            )
        }
    }

    func testConnectionFailureOnLoginAndGreetingFailuresBecomeConnectionFailedWithoutThePassword() {
        let cases: [(IMAPError, SwiftMailClient.Command)] = [
            (.connectionFailed("reset secret"), .login),
            (.greetingFailed("reset secret"), .login),
            (.greetingFailed("reset secret"), .capability),
        ]
        for (error, command) in cases {
            XCTAssertEqual(
                irisError(error, command),
                .connectionFailed(account: "work", host: "imap.example.com", port: 993, reason: "reset <password>"),
                "\(error) on \(command)"
            )
        }
    }

    func testConnectionFailureAfterLoginBecomesConnectionLostWithoutThePassword() {
        let commands: [SwiftMailClient.Command] = [
            .capability, .list, .examine(mailbox: "INBOX"), .fetchEnvelopes, .fetchRawMessage(uid: 42),
        ]
        for command in commands {
            XCTAssertEqual(
                irisError(IMAPError.connectionFailed("Server terminated connection: secret"), command),
                .connectionLost(
                    account: "work", command: command.name, reason: "Server terminated connection: <password>"
                ),
                "\(command)"
            )
        }
    }

    func testOtherIMAPErrorsBecomeServerErrorsNamingTheCommand() {
        XCTAssertEqual(
            irisError(IMAPError.commandFailed("NO [UNAVAILABLE] secret"), .list),
            .serverError(account: "work", command: "LIST", reason: "Command failed: NO [UNAVAILABLE] <password>")
        )
        XCTAssertEqual(
            irisError(IMAPError.selectFailed("NO"), .fetchEnvelopes),
            .serverError(account: "work", command: "FETCH", reason: "Select mailbox failed: NO"),
            "selectFailed means an unknown mailbox only for EXAMINE"
        )
    }

    func testOtherErrorsOnLoginAreNetworkFailuresAndBecomeConnectionFailed() {
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

    func testOtherErrorsAfterLoginBecomeConnectionLostWithoutThePassword() {
        struct ConnectionReset: Error, CustomStringConvertible {
            var description: String { "read(descriptor:pointer:size:): Connection reset by peer (secret)" }
        }
        let commands: [SwiftMailClient.Command] = [
            .capability, .list, .examine(mailbox: "INBOX"), .fetchEnvelopes, .fetchRawMessage(uid: 42),
        ]
        for command in commands {
            XCTAssertEqual(
                irisError(ConnectionReset(), command),
                .connectionLost(
                    account: "work",
                    command: command.name,
                    reason: "read(descriptor:pointer:size:): Connection reset by peer (<password>)"
                ),
                "\(command)"
            )
        }
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

    func testMailboxInfoKeepsTheWireName() {
        for wire in ["[Gmail]/Entw&APw-rfe", "R&-D", "INBOX", "R&D"] {
            let info = Mailbox.Info(name: wire, attributes: [], hierarchyDelimiter: "/")
            XCTAssertEqual(MailboxInfo(swiftMail: info).name, wire, "MailReader decodes the name, not the client")
        }
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
