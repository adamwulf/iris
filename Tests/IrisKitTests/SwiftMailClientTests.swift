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
        XCTAssertEqual(SwiftMailClient.Command.headerSearch.name, "SEARCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchEnvelopes.name, "FETCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchThreadHeaders.name, "FETCH")
        XCTAssertEqual(SwiftMailClient.Command.fetchRawMessage.name, "FETCH")
        XCTAssertEqual(SwiftMailClient.Command.select(mailbox: "INBOX").name, "SELECT")
        XCTAssertEqual(SwiftMailClient.Command.store.name, "STORE")
        XCTAssertEqual(SwiftMailClient.Command.append(mailbox: "Drafts").name, "APPEND")
    }

    // MARK: - APPEND errors

    func testAppendLimitExceededBecomesDraftTooLarge() {
        XCTAssertEqual(
            irisError(IMAPError.appendLimitExceeded(2_000_000, 1_000_000), .append(mailbox: "Drafts")),
            .draftTooLarge(account: "work", size: 2_000_000, limit: 1_000_000)
        )
    }

    /// The server may have saved the draft, so the error must not just say "try again".
    func testTimeoutDuringAppendBecomesDraftMayBeSavedWithTheWireName() {
        XCTAssertEqual(
            irisError(IMAPError.timeout, .append(mailbox: "[Gmail]/Entw&APw-rfe")),
            .draftMayBeSaved(
                account: "work", mailbox: "[Gmail]/Entw&APw-rfe", reason: "the server did not answer APPEND in time"
            ),
            "the error holds the wire name; MailWriter puts back the decoded name"
        )
    }

    func testBrokenConnectionDuringAppendBecomesDraftMayBeSavedWithoutThePassword() {
        struct ConnectionReset: Error, CustomStringConvertible {
            var description: String { "Connection reset by peer (secret)" }
        }
        XCTAssertEqual(
            irisError(IMAPError.connectionFailed("Server terminated connection: secret"), .append(mailbox: "Drafts")),
            .draftMayBeSaved(account: "work", mailbox: "Drafts", reason: "Server terminated connection: <redacted>")
        )
        XCTAssertEqual(
            irisError(ConnectionReset(), .append(mailbox: "Drafts")),
            .draftMayBeSaved(account: "work", mailbox: "Drafts", reason: "Connection reset by peer (<redacted>)")
        )
    }

    func testRefusedAppendBecomesAServerErrorNamingAPPEND() {
        XCTAssertEqual(
            irisError(IMAPError.commandFailed("NO [OVERQUOTA] secret"), .append(mailbox: "Drafts")),
            .serverError(account: "work", command: "APPEND", reason: "Command failed: NO [OVERQUOTA] <redacted>")
        )
    }

    func testAppendErrorsOfAGoogleAccountNeverShowTheRefreshTokenOrClientSecret() {
        struct ConnectionReset: Error, CustomStringConvertible {
            var description: String { "reset: client-secret 1//refresh-token" }
        }
        let echo = "client-secret 1//refresh-token"
        for error in [IMAPError.connectionFailed(echo), IMAPError.commandFailed(echo), ConnectionReset()] as [any Error] {
            let mapped = SwiftMailClient.irisError(for: error, command: .append(mailbox: "Drafts"), account: googleAccount)
            let message = mapped.errorDescription ?? ""
            XCTAssertTrue(message.contains("<redacted> <redacted>"), message)
            for secret in ["client-secret", "1//refresh-token"] {
                XCTAssertFalse(message.contains(secret), "\(secret) in \(message)")
            }
        }
    }

    // MARK: - Drafts

    /// `createDraft` adds `\Draft` itself; iris adds `\Seen`, as Apple Mail saves its own drafts.
    func testADraftIsSavedAsSeen() {
        XCTAssertEqual(SwiftMailClient.additionalDraftFlags, [.seen])
    }

    private let reply = DraftMessage(
        from: MailAddress(name: "Me", address: "me@example.com"),
        to: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
        cc: [MailAddress(name: nil, address: "bob@example.com")],
        subject: "Re: Q4 plan",
        inReplyTo: "<m3@example.com>",
        references: (1...3).map { "<message-\($0)-0123456789@mail.example.com>" },
        markdown: "Looks *good*.\n\nOn 2026-10-24 13:42 CDT, Jane Doe wrote:\n> Can you look?",
        html: "<p>Looks <em>good</em>.</p>\n",
        attachments: []
    )

    func testEmailFromADraftHasItsHeadersAndBothParts() {
        // As IMAPServer.append(email:to:flags:internalDate:) writes it.
        let content = Email(draft: reply).constructContent(use8BitMIME: true)

        XCTAssertTrue(content.contains("From: Me <me@example.com>\r\n"), content)
        XCTAssertTrue(content.contains("To: Jane Doe <jane@example.com>\r\n"), content)
        XCTAssertTrue(content.contains("Cc: bob@example.com\r\n"), content)
        XCTAssertTrue(content.contains("Subject: Re: Q4 plan\r\n"), content)
        XCTAssertTrue(content.contains("In-Reply-To: <m3@example.com>\r\n"), content)
        XCTAssertTrue(
            content.contains(
                "References: <message-1-0123456789@mail.example.com>\r\n"
                    + " <message-2-0123456789@mail.example.com>\r\n"
                    + " <message-3-0123456789@mail.example.com>\r\n"
            ),
            "SwiftMail writes the folded value as it is: \(content)"
        )
        XCTAssertTrue(content.contains("Content-Type: multipart/alternative;"), content)
        XCTAssertTrue(content.contains("Content-Type: text/plain; charset=UTF-8\r\n"), content)
        XCTAssertTrue(content.contains("Looks *good*.\n\nOn 2026-10-24 13:42 CDT, Jane Doe wrote:\n> Can you look?"), content)
        XCTAssertTrue(content.contains("Content-Type: text/html; charset=UTF-8\r\n"), content)
        XCTAssertTrue(content.contains("<p>Looks <em>good</em>.</p>"), content)
        XCTAssertTrue(content.contains("Message-Id: <"), "SwiftMail makes a new Message-ID")
        XCTAssertTrue(content.contains("\r\nDate: "), "SwiftMail dates the draft now")
    }

    func testEmailFromADraftWithoutThreadingHasNoThreadingHeaders() {
        let first = DraftMessage(
            from: reply.from, to: reply.to, cc: [], subject: "Re:", inReplyTo: nil, references: [],
            markdown: "Hi", html: "<p>Hi</p>\n", attachments: []
        )
        let email = Email(draft: first)
        XCTAssertNil(email.additionalHeaders)
        let content = email.constructContent()
        XCTAssertFalse(content.contains("In-Reply-To:"), content)
        XCTAssertFalse(content.contains("References:"), content)
        XCTAssertFalse(content.contains("\r\nCc:"), content)
    }

    // MARK: - Draft attachments

    /// 60 bytes: base64 makes 80 characters, more than one line of 76.
    private let plan = DraftAttachment(
        filename: "Q4 plan.pdf", mimeType: "application/pdf", data: Data((0..<60).map { UInt8($0) })
    )
    private let empty = DraftAttachment(filename: "empty.txt", mimeType: "text/plain", data: Data())

    /// `reply` with `attachments`.
    private func draft(attaching attachments: [DraftAttachment]) -> DraftMessage {
        DraftMessage(
            from: reply.from, to: reply.to, cc: reply.cc, subject: reply.subject, inReplyTo: reply.inReplyTo,
            references: reply.references, markdown: reply.markdown, html: reply.html, attachments: attachments
        )
    }

    /// The type in the message's own Content-Type header: the first one, after the headers.
    private func topLevelContentType(of content: String) -> String? {
        guard let start = content.range(of: "\r\nContent-Type: ")?.upperBound else {
            return nil
        }
        return String(content[start...].prefix { $0 != ";" && !$0.isNewline })
    }

    func testEmailFromADraftWithoutAttachmentsStaysMultipartAlternative() {
        let email = Email(draft: reply)
        XCTAssertNil(email.attachments)

        let content = email.constructContent(use8BitMIME: true)
        XCTAssertEqual(topLevelContentType(of: content), "multipart/alternative", content)
        XCTAssertFalse(content.contains("multipart/mixed"), content)
        XCTAssertFalse(content.contains("Content-Disposition:"), content)
    }

    func testEmailFromADraftHasItsAttachmentsAsRegularOnesInOrder() throws {
        let email = Email(draft: draft(attaching: [plan, empty]))

        let attachments = try XCTUnwrap(email.attachments)
        XCTAssertEqual(attachments.map(\.filename), ["Q4 plan.pdf", "empty.txt"])
        XCTAssertEqual(attachments.map(\.mimeType), ["application/pdf", "text/plain"])
        XCTAssertEqual(attachments.map(\.data), [plan.data, Data()])
        XCTAssertEqual(attachments.map(\.isInline), [false, false])
        XCTAssertEqual(attachments.map(\.contentID), [nil, nil])
    }

    func testContentOfADraftWithAttachmentsIsMultipartMixedWithABase64PartPerFile() throws {
        // As IMAPServer.append(email:to:flags:internalDate:) writes it.
        let content = Email(draft: draft(attaching: [plan, empty])).constructContent(use8BitMIME: true)

        XCTAssertEqual(topLevelContentType(of: content), "multipart/mixed", content)
        let boundaryStart = try XCTUnwrap(content.range(of: "multipart/mixed; boundary=\"")?.upperBound)
        let boundary = String(content[boundaryStart...].prefix { $0 != "\"" })
        XCTAssertEqual(
            content.components(separatedBy: "--\(boundary)\r\n").count - 1, 3,
            "one part for the text and HTML, and one per file: \(content)"
        )
        XCTAssertTrue(content.hasSuffix("--\(boundary)--\r\n"), content)

        // The text and HTML first, as without attachments, then the files in order.
        let markers = [
            "Content-Type: multipart/alternative;", "Content-Type: text/plain; charset=UTF-8\r\n",
            "Content-Type: text/html; charset=UTF-8\r\n", "filename=\"Q4 plan.pdf\"", "filename=\"empty.txt\"",
        ]
        let positions = markers.compactMap { content.range(of: $0)?.lowerBound }
        XCTAssertEqual(positions.count, markers.count, content)
        XCTAssertEqual(positions, positions.sorted(), content)

        let encoded = plan.data.base64EncodedString()
        XCTAssertTrue(
            content.contains(
                "Content-Type: application/pdf\r\nContent-Transfer-Encoding: base64\r\n"
                    + "Content-Disposition: attachment; filename=\"Q4 plan.pdf\"\r\n\r\n"
                    + String(encoded.prefix(76)) + "\r\n" + String(encoded.dropFirst(76)) + "\r\n"
            ),
            "base64 in lines of 76 characters that end with CRLF: \(content)"
        )
        XCTAssertTrue(
            content.contains(
                "Content-Type: text/plain\r\nContent-Transfer-Encoding: base64\r\n"
                    + "Content-Disposition: attachment; filename=\"empty.txt\"\r\n\r\n\r\n"
            ),
            "an empty file is an empty part: \(content)"
        )
    }

    /// SwiftMail writes a filename that is not printable ASCII as one RFC 2231
    /// parameter: `filename*=` with the name in UTF-8, percent-encoded.
    func testANonASCIIFilenameIsWrittenAsAnRFC2231Parameter() {
        let resume = DraftAttachment(filename: "R\u{E9}sum\u{E9}.pdf", mimeType: "application/pdf", data: Data("%PDF".utf8))

        let content = Email(draft: draft(attaching: [resume])).constructContent(use8BitMIME: true)

        XCTAssertTrue(
            content.contains("Content-Disposition: attachment; filename*=UTF-8''R%C3%A9sum%C3%A9.pdf\r\n"), content
        )
        XCTAssertFalse(content.contains("filename=\""), "only the encoded form: \(content)")
    }

    func testRefusedHeaderSearchIsAServerErrorNotAFilterError() {
        // The thread search has no filter options, so the filter advice in searchFailed does not apply.
        XCTAssertEqual(
            irisError(IMAPError.commandFailed("BAD Could not parse command secret"), .headerSearch),
            .serverError(account: "work", command: "SEARCH", reason: "Command failed: BAD Could not parse command <redacted>")
        )
        XCTAssertEqual(irisError(IMAPError.timeout, .headerSearch), .serverTimedOut(account: "work", command: "SEARCH"))
        XCTAssertEqual(irisError(IMAPError.timeout, .fetchThreadHeaders), .serverTimedOut(account: "work", command: "FETCH"))
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
            MessageFilter(
                unread: true, flagged: true, from: "jane", to: "bob", subject: "Q4 plan", search: "budget",
                since: since, before: before
            ),
            [
                .unseen, .flagged, .from("jane"), .to("bob"), .subject("Q4 plan"), .text("budget"),
                .since(since.start), .before(before.start),
            ]
        )
    }

    func testSearchCriteriaLeaveOutConditionsThatAreNotSet() throws {
        assertCriteria(MessageFilter(unread: true), [.unseen])
        assertCriteria(MessageFilter(flagged: true), [.flagged])
        assertCriteria(MessageFilter(from: "Jürgen"), [.from("Jürgen")])
        assertCriteria(MessageFilter(to: "bob"), [.to("bob")])
        assertCriteria(MessageFilter(search: "invoice"), [.text("invoice")])
        let since = try CalendarDay(parsing: "2026-10-01")
        assertCriteria(MessageFilter(since: since), [.since(since.start)])
    }

    func testSubjectSearchHasOneSubjectKeyPerText() {
        XCTAssertEqual(
            "\(SwiftMailClient.subjectSearchCriteria(["introduction", "application", "josh"]))",
            "\([SearchCriteria.subject("introduction"), .subject("application"), .subject("josh")])"
        )
        XCTAssertEqual(
            "\(SwiftMailClient.subjectSearchCriteria(["josh ←→ anthony"]))",
            "\([SearchCriteria.subject("josh ←→ anthony")])"
        )
    }

    func testMessageIDSearchForOneIDIsOneHeaderKey() {
        XCTAssertEqual(
            "\(SwiftMailClient.messageIDSearchCriteria(["<a@x>"]))",
            "\(SearchCriteria.header("Message-ID", "<a@x>"))"
        )
    }

    func testMessageIDSearchJoinsTheIDsWithABalancedOr() {
        let criteria = SwiftMailClient.messageIDSearchCriteria(["<a@x>", "<b@x>", "<c@x>", "<d@x>", "<e@x>"])
        let expected: SearchCriteria = .or(
            .or(.header("Message-ID", "<a@x>"), .header("Message-ID", "<b@x>")),
            .or(.header("Message-ID", "<c@x>"), .or(.header("Message-ID", "<d@x>"), .header("Message-ID", "<e@x>")))
        )
        XCTAssertEqual("\(criteria)", "\(expected)")
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

    // MARK: - Thread headers

    func testThreadHeadersKeepTheMessageIDsWithAngleBrackets() throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let received = Date(timeIntervalSince1970: 1_000_060)
        let info = MessageInfo(
            sequenceNumber: SequenceNumber(3),
            uid: UID(103),
            subject: "Re: Budget",
            date: date,
            internalDate: received,
            messageId: MessageID("<c@example.com>"),
            inReplyTo: MessageID("<b@example.com>"),
            references: [MessageID("<a@example.com>"), MessageID("<b@example.com>")].compactMap { $0 }
        )

        XCTAssertEqual(ThreadHeaders(swiftMail: info), ThreadHeaders(
            uid: 103,
            messageID: "<c@example.com>",
            inReplyTo: "<b@example.com>",
            references: ["<a@example.com>", "<b@example.com>"],
            subject: "Re: Budget",
            date: date,
            internalDate: received
        ))
    }

    func testThreadHeadersWithoutTheHeadersAreEmpty() throws {
        let headers = try XCTUnwrap(ThreadHeaders(swiftMail: MessageInfo(sequenceNumber: SequenceNumber(3), uid: UID(103))))
        XCTAssertNil(headers.messageID)
        XCTAssertNil(headers.inReplyTo)
        XCTAssertEqual(headers.references, [])
        XCTAssertNil(headers.subject)
    }

    func testThreadHeadersWithoutAUIDAreLeftOut() {
        XCTAssertNil(ThreadHeaders(swiftMail: MessageInfo(sequenceNumber: SequenceNumber(3))))
    }
}
