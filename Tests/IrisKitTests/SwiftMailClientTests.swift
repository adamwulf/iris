import Foundation
import SwiftMail
import XCTest
@testable import IrisKit

/// The parts of `SwiftMailClient` that need no server: the TLS choice, the
/// error mapping, and the mailbox and envelope conversions.
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
            irisError(IMAPError.timeout, .fetchRawMessage),
            .messageDownloadTimedOut(seconds: SwiftMailClient.rawMessageTimeoutSeconds)
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
        let commands: [SwiftMailClient.Command] = [
            .capability, .list, .examine(mailbox: "INBOX"), .search, .fetchEnvelopes,
        ]
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
            .capability, .list, .examine(mailbox: "INBOX"), .search, .fetchEnvelopes, .fetchRawMessage,
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

    func testRefusedSearchBecomesSearchFailedWithoutThePassword() {
        XCTAssertEqual(
            irisError(IMAPError.commandFailed("BAD Could not parse command secret"), .search),
            .searchFailed(account: "work", reason: "Command failed: BAD Could not parse command <password>")
        )
        let badCharset = IMAPError.searchCharsetNotSupported(supportedCharsets: ["US-ASCII"], reason: "NO [BADCHARSET]")
        XCTAssertEqual(
            irisError(badCharset, .search),
            .searchFailed(account: "work", reason: badCharset.description)
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
            .capability, .list, .examine(mailbox: "INBOX"), .search, .fetchEnvelopes, .fetchRawMessage,
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
        XCTAssertEqual(SwiftMailClient.Command.search.name, "SEARCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchEnvelopes.name, "FETCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchRawMessage.name, "FETCH")
    }

    // MARK: - Search

    /// SearchCriteria is not Equatable, so the tests compare descriptions.
    private func assertCriteria(
        _ filter: MessageFilter,
        _ expected: [SearchCriteria],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            "\(SwiftMailClient.searchCriteria(for: filter))", "\(expected)", file: file, line: line
        )
    }

    func testSearchCriteriaHaveOneKeyPerConditionInHelpOrder() throws {
        let since = try CalendarDay(parsing: "2026-10-01")
        let before = try CalendarDay(parsing: "2026-11-01")
        assertCriteria(
            MessageFilter(unread: true, flagged: true, from: "jane", subject: "Q4 plan", since: since, before: before),
            [.unseen, .flagged, .from("jane"), .subject("Q4 plan"), .since(since.start), .before(before.start)]
        )
    }

    func testSearchCriteriaLeaveOutConditionsThatAreNotSet() throws {
        assertCriteria(MessageFilter(unread: true), [.unseen])
        assertCriteria(MessageFilter(flagged: true), [.flagged])
        assertCriteria(MessageFilter(from: "Jürgen"), [.from("Jürgen")])
        let since = try CalendarDay(parsing: "2026-10-01")
        assertCriteria(MessageFilter(since: since), [.since(since.start)])
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

    // MARK: - Envelopes

    func testEnvelopeIsSeenOnlyWithTheSeenFlag() throws {
        let read = MessageInfo(sequenceNumber: SequenceNumber(3), uid: UID(103), subject: "Hi", flags: [.flagged, .seen])
        let unread = MessageInfo(sequenceNumber: SequenceNumber(4), uid: UID(104), flags: [.flagged, .answered])
        let noFlags = MessageInfo(sequenceNumber: SequenceNumber(5), uid: UID(105))

        let envelope = try XCTUnwrap(MessageEnvelope(swiftMail: read))
        XCTAssertEqual(envelope.sequenceNumber, 3)
        XCTAssertEqual(envelope.uid, 103)
        XCTAssertEqual(envelope.subject, "Hi")
        XCTAssertTrue(envelope.seen)
        XCTAssertEqual(MessageEnvelope(swiftMail: unread)?.seen, false)
        XCTAssertEqual(MessageEnvelope(swiftMail: noFlags)?.seen, false)
    }

    func testEnvelopeWithoutAUIDIsLeftOut() {
        XCTAssertNil(MessageEnvelope(swiftMail: MessageInfo(sequenceNumber: SequenceNumber(3), flags: [.seen])))
    }

    /// Zoho keeps the header's quotes in the ENVELOPE name.
    func testEnvelopeSenderNameLosesTheQuotesTheServerKept() throws {
        var info = MessageInfo(sequenceNumber: SequenceNumber(3), uid: UID(103))
        info.fromAddresses = [.mailbox(EmailAddress(name: #""Doe, Jane""#, address: "jane@example.com"))]

        let sender = try XCTUnwrap(MessageEnvelope(swiftMail: info)?.from)
        XCTAssertEqual(sender.name, "Doe, Jane")
        XCTAssertEqual(sender.address, "jane@example.com")
    }
}
