import Foundation
import SwiftMail
import XCTest
@testable import IrisKit

/// The parts of `SwiftMailClient` that need no server: the TLS choice, the
/// error mapping, and the mailbox and envelope conversions.
final class SwiftMailClientTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )

    private let googleAccount = Account(
        name: "personal", host: "imap.gmail.com", port: 993, username: "me@gmail.com",
        authentication: .google(
            GoogleClient(clientID: "id.apps.googleusercontent.com", clientSecret: "client-secret"),
            refreshToken: "1//refresh-token"
        )
    )

    private func irisError(_ error: any Error, _ command: SwiftMailClient.Command) -> IrisError {
        SwiftMailClient.irisError(for: error, command: command, account: account)
    }

    /// The mapping for the Google account during AUTHENTICATE, which sent the access token `ya29.access`.
    /// Only AUTHENTICATE passes the access token, as in `SwiftMailClient.login()`.
    private func googleError(_ error: any Error) -> IrisError {
        SwiftMailClient.irisError(for: error, command: .authenticate, account: googleAccount, accessToken: "ya29.access")
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
            account: "work", username: "me@example.com", host: "imap.example.com", reason: "NO bad <redacted>"
        )
        XCTAssertEqual(irisError(IMAPError.loginFailed("NO bad secret"), .login), expected)
        XCTAssertEqual(irisError(IMAPError.authFailed("NO bad secret"), .login), expected)
    }

    func testSelectFailedOnExamineOrSelectBecomesUnknownMailbox() {
        let opens: [(String) -> SwiftMailClient.Command] = [
            { .examine(mailbox: $0) },
            { .select(mailbox: $0) },
        ]
        for open in opens {
            XCTAssertEqual(
                irisError(IMAPError.selectFailed("NO [NONEXISTENT] secret"), open("Nope")),
                .unknownMailbox(account: "work", name: "Nope", reason: "NO [NONEXISTENT] <redacted>")
            )
            XCTAssertEqual(
                irisError(IMAPError.selectFailed("NO"), open("[Gmail]/Entw&APw-rfe")),
                .unknownMailbox(account: "work", name: "[Gmail]/Entw&APw-rfe", reason: "NO"),
                "the error holds the wire name; MailReader and MailWriter put back the name the user typed"
            )
        }
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
            .capability, .list, .examine(mailbox: "INBOX"), .search, .fetchEnvelopes, .select(mailbox: "INBOX"), .store,
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
                .connectionFailed(account: "work", host: "imap.example.com", port: 993, reason: "reset <redacted>"),
                "\(error) on \(command)"
            )
        }
    }

    func testConnectionFailureAfterLoginBecomesConnectionLostWithoutThePassword() {
        let commands: [SwiftMailClient.Command] = [
            .capability, .list, .examine(mailbox: "INBOX"), .search, .fetchEnvelopes, .fetchRawMessage,
            .select(mailbox: "INBOX"), .store,
        ]
        for command in commands {
            XCTAssertEqual(
                irisError(IMAPError.connectionFailed("Server terminated connection: secret"), command),
                .connectionLost(
                    account: "work", command: command.name, reason: "Server terminated connection: <redacted>"
                ),
                "\(command)"
            )
        }
    }

    func testOtherIMAPErrorsBecomeServerErrorsNamingTheCommand() {
        XCTAssertEqual(
            irisError(IMAPError.commandFailed("NO [UNAVAILABLE] secret"), .list),
            .serverError(account: "work", command: "LIST", reason: "Command failed: NO [UNAVAILABLE] <redacted>")
        )
        XCTAssertEqual(
            irisError(IMAPError.selectFailed("NO"), .fetchEnvelopes),
            .serverError(account: "work", command: "FETCH", reason: "Select mailbox failed: NO"),
            "selectFailed means an unknown mailbox only for EXAMINE and SELECT"
        )
        XCTAssertEqual(
            irisError(IMAPError.storeFailed("NO [READ-ONLY] secret"), .store),
            .serverError(account: "work", command: "STORE", reason: "Store failed: NO [READ-ONLY] <redacted>")
        )
    }

    func testRefusedSearchBecomesSearchFailedWithoutThePassword() {
        XCTAssertEqual(
            irisError(IMAPError.commandFailed("BAD Could not parse command secret"), .search),
            .searchFailed(account: "work", reason: "Command failed: BAD Could not parse command <redacted>")
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
                account: "work", host: "imap.example.com", port: 993, reason: "handshake failed for <redacted>"
            )
        )
    }

    func testOtherErrorsAfterLoginBecomeConnectionLostWithoutThePassword() {
        struct ConnectionReset: Error, CustomStringConvertible {
            var description: String { "read(descriptor:pointer:size:): Connection reset by peer (secret)" }
        }
        let commands: [SwiftMailClient.Command] = [
            .capability, .list, .examine(mailbox: "INBOX"), .search, .fetchEnvelopes, .fetchRawMessage,
            .select(mailbox: "INBOX"), .store,
        ]
        for command in commands {
            XCTAssertEqual(
                irisError(ConnectionReset(), command),
                .connectionLost(
                    account: "work",
                    command: command.name,
                    reason: "read(descriptor:pointer:size:): Connection reset by peer (<redacted>)"
                ),
                "\(command)"
            )
        }
    }

    // MARK: - Google sign-in errors

    func testRefusedXOAUTH2BecomesGoogleLoginRefusedNotLoginFailed() {
        // SwiftMail's XOAUTH2 handler reports the tagged NO, with the server's JSON challenge after it.
        let refusal = IMAPError.authFailed(
            #"no(NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)) ({"status":"400","schemes":"Bearer"})"#
        )
        XCTAssertEqual(
            googleError(refusal),
            .googleLoginRefused(
                account: "personal",
                username: "me@gmail.com",
                host: "imap.gmail.com",
                reason: #"no(NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)) ({"status":"400","schemes":"Bearer"})"#
            )
        )
        XCTAssertEqual(
            googleError(IMAPError.loginFailed("NO")),
            .googleLoginRefused(account: "personal", username: "me@gmail.com", host: "imap.gmail.com", reason: "NO")
        )
    }

    func testAuthenticateErrorsNeverShowTheAccessTokenRefreshTokenOrClientSecret() {
        let echo = "user=me@gmail.com auth=Bearer ya29.access client-secret 1//refresh-token"
        let errors = [
            googleError(IMAPError.authFailed(echo)),
            googleError(IMAPError.connectionFailed(echo)),
            googleError(IMAPError.commandFailed(echo)),
        ]
        for error in errors {
            let message = error.errorDescription ?? ""
            XCTAssertTrue(message.contains("auth=Bearer <redacted> <redacted> <redacted>"), message)
            for secret in ["ya29.access", "client-secret", "1//refresh-token"] {
                XCTAssertFalse(message.contains(secret), "\(secret) in \(message)")
            }
        }
    }

    func testErrorsAfterAuthenticateNeverShowTheRefreshTokenOrClientSecret() {
        // After AUTHENTICATE, iris passes no access token, as in production.
        let echo = "client-secret 1//refresh-token"
        let cases: [(any Error, SwiftMailClient.Command)] = [
            (IMAPError.connectionFailed(echo), .list),
            (IMAPError.commandFailed(echo), .search),
            (IMAPError.selectFailed(echo), .examine(mailbox: "INBOX")),
            (IMAPError.commandFailed(echo), .fetchEnvelopes),
        ]
        for (error, command) in cases {
            let message = SwiftMailClient.irisError(for: error, command: command, account: googleAccount)
                .errorDescription ?? ""
            XCTAssertTrue(message.contains("<redacted> <redacted>"), message)
            for secret in ["client-secret", "1//refresh-token"] {
                XCTAssertFalse(message.contains(secret), "\(secret) in \(message)")
            }
        }
    }

    func testAServerWithoutXOAUTH2PointsAtTheHost() {
        guard case .invalidSetting(let key, let reason) = googleError(
            IMAPError.unsupportedAuthMechanism("XOAUTH2 not advertised by server")
        ) else {
            return XCTFail("expected invalidSetting")
        }
        XCTAssertEqual(key, "IRIS_PERSONAL_IMAP_HOST")
        XCTAssertTrue(reason.contains("imap.gmail.com"), reason)
    }

    func testTimeoutAndNetworkFailuresOnAuthenticateAreConnectionFailures() {
        XCTAssertEqual(
            googleError(IMAPError.timeout),
            .connectionFailed(
                account: "personal", host: "imap.gmail.com", port: 993,
                reason: "the server did not answer AUTHENTICATE in time"
            )
        )
        XCTAssertEqual(
            googleError(IMAPError.connectionFailed("reset")),
            .connectionFailed(account: "personal", host: "imap.gmail.com", port: 993, reason: "reset")
        )
        struct TLSFailure: Error, CustomStringConvertible {
            var description: String { "handshake failed" }
        }
        XCTAssertEqual(
            googleError(TLSFailure()),
            .connectionFailed(account: "personal", host: "imap.gmail.com", port: 993, reason: "handshake failed")
        )
    }

    func testTokenEndpointErrorsPassThroughAuthenticate() {
        XCTAssertEqual(googleError(IrisError.googleSignInExpired(account: "personal")), .googleSignInExpired(account: "personal"))
    }

    func testCommandNames() {
        XCTAssertEqual(SwiftMailClient.Command.login.name, "LOGIN")
        XCTAssertEqual(SwiftMailClient.Command.authenticate.name, "AUTHENTICATE")
        XCTAssertEqual(SwiftMailClient.Command.capability.name, "CAPABILITY")
        XCTAssertEqual(SwiftMailClient.Command.list.name, "LIST")
        XCTAssertEqual(SwiftMailClient.Command.examine(mailbox: "INBOX").name, "EXAMINE")
        XCTAssertEqual(SwiftMailClient.Command.search.name, "SEARCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchEnvelopes.name, "FETCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchRawMessage.name, "FETCH")
        XCTAssertEqual(SwiftMailClient.Command.select(mailbox: "INBOX").name, "SELECT")
        XCTAssertEqual(SwiftMailClient.Command.store.name, "STORE")
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

    // MARK: - Store

    func testReadAddsSeenAndUnreadRemovesIt() {
        XCTAssertEqual(SwiftMailClient.storeOperation(seen: true), .add)
        XCTAssertEqual(SwiftMailClient.storeOperation(seen: false), .remove)
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
