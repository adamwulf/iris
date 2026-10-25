import Foundation
import XCTest
@testable import IrisKit

final class DraftWriterTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )
    private let me = MailAddress(name: "Me", address: "me@example.com")
    private let drafts = MailboxInfo(name: "Drafts", attributes: [#"\Drafts"#])

    private var draft: DraftMessage {
        DraftMessage(
            from: me,
            to: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
            cc: [],
            subject: "Re: Q4 plan",
            inReplyTo: nil,
            references: [],
            markdown: "Looks good.",
            html: "<p>Looks good.</p>\n"
        )
    }

    /// A writer that reads from `mail` and saves through `client`.
    private func writer(_ client: FakeDraftClient, reading mail: FakeMailClient = FakeMailClient()) -> DraftWriter {
        DraftWriter(reader: MailReader(account: account, makeClient: { _ in mail }), makeClient: { _ in client })
    }

    private func assertThrows<T>(
        _ expected: IrisError,
        _ body: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected), but nothing was thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? IrisError, expected, file: file, line: line)
        }
    }

    // MARK: - save

    func testSaveAppendsToTheDraftsMailboxAndGivesTheIrisID() async throws {
        let client = FakeDraftClient(
            mailboxes: [MailboxInfo(name: "INBOX", attributes: []), drafts, MailboxInfo(name: "Sent", attributes: [#"\Sent"#])],
            appendedUID: 42
        )

        let saved = try await writer(client).save(draft)

        XCTAssertEqual(saved, SavedDraft(mailbox: "Drafts", irisID: IrisID(account: "work", mailbox: "Drafts", uid: 42)))
        XCTAssertNil(saved.missingIDNote)
        let calls = await client.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "Drafts"), .logout])
    }

    /// LIST gives wire names, and the attributes can come in a second entry for the name.
    func testSaveAppendsToTheWireNameAndGivesTheDecodedNameInTheIrisID() async throws {
        let client = FakeDraftClient(
            mailboxes: [
                MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: []),
                MailboxInfo(name: "INBOX", attributes: []),
                MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: [#"\Drafts"#]),
            ],
            appendedUID: 7
        )

        let saved = try await writer(client).save(draft)

        XCTAssertEqual(saved.mailbox, "[Gmail]/Entwürfe")
        XCTAssertEqual(saved.irisID?.description, "work/[Gmail]/Entwürfe/7")
        let calls = await client.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "[Gmail]/Entw&APw-rfe"), .logout])
    }

    func testSaveWithoutAUIDFromTheServerHasNoIrisIDAndANote() async throws {
        let client = FakeDraftClient(mailboxes: [drafts], appendedUID: nil)

        let saved = try await writer(client).save(draft)

        XCTAssertEqual(saved, SavedDraft(mailbox: "Drafts", irisID: nil))
        XCTAssertEqual(
            saved.missingIDNote,
            "The draft was saved in \"Drafts\", but the server did not report its UID, so iris cannot give its iris ID."
        )
    }

    func testSaveWithoutADraftsMailboxThrowsAndLogsOut() async {
        let client = FakeDraftClient(mailboxes: [MailboxInfo(name: "INBOX", attributes: []), MailboxInfo(name: "Drafts", attributes: [])])

        await assertThrows(.draftsMailboxNotFound(account: "work")) { try await self.writer(client).save(self.draft) }

        let calls = await client.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .logout], "a mailbox named Drafts without the attribute is not used")
    }

    func testFailedLoginStillLogsOutAndSavesNothing() async {
        let failure = IrisError.loginFailed(account: "work", username: "me@example.com", host: "imap.example.com", reason: "NO")
        let client = FakeDraftClient(mailboxes: [drafts], errors: [.login: failure])

        await assertThrows(failure) { try await self.writer(client).save(self.draft) }

        let calls = await client.calls
        XCTAssertEqual(calls, [.login, .logout])
    }

    func testFailedListStillLogsOut() async {
        let failure = IrisError.serverError(account: "work", command: "LIST", reason: "NO")
        let client = FakeDraftClient(mailboxes: [drafts], errors: [.listMailboxes: failure])

        await assertThrows(failure) { try await self.writer(client).save(self.draft) }

        let calls = await client.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .logout])
    }

    func testFailedAppendStillLogsOut() async {
        let failure = IrisError.draftTooLarge(account: "work", size: 2000, limit: 1000)
        let client = FakeDraftClient(mailboxes: [drafts], errors: [.appendDraft: failure])

        await assertThrows(failure) { try await self.writer(client).save(self.draft) }

        let calls = await client.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "Drafts"), .logout])
    }

    func testDraftMayBeSavedGetsTheDecodedMailboxName() async {
        let client = FakeDraftClient(
            mailboxes: [MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: [#"\Drafts"#])],
            errors: [.appendDraft: IrisError.draftMayBeSaved(account: "work", mailbox: "[Gmail]/Entw&APw-rfe", reason: "timeout")]
        )

        await assertThrows(.draftMayBeSaved(account: "work", mailbox: "[Gmail]/Entwürfe", reason: "timeout")) {
            try await self.writer(client).save(self.draft)
        }

        let calls = await client.calls
        XCTAssertEqual(calls.last, .logout)
    }

    // MARK: - saveReply

    private let original = """
        From: Jane Doe <jane@example.com>
        To: Me <me@example.com>, Bob <bob@example.com>
        Subject: Q4 plan
        Date: Sat, 24 Oct 2026 13:42:00 -0500
        Message-ID: <m3@example.com>
        References: <m1@example.com>

        Can you look at the plan?
        """

    private func inbox(holding text: String, uid: UInt32) -> FakeMailClient {
        FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: uid + 1)],
            rawMessages: [uid: Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)]
        )
    }

    func testSaveReplyReadsTheOriginalThenSavesTheReplyInASecondSession() async throws {
        let mail = inbox(holding: original, uid: 9)
        let client = FakeDraftClient(mailboxes: [drafts], appendedUID: 43)

        let saved = try await writer(client, reading: mail).saveReply(
            to: IrisID(account: "work", mailbox: "INBOX", uid: 9),
            body: "Looks good.",
            from: me,
            replyAll: true,
            quote: true,
            timeZone: TimeZone(identifier: "America/Chicago")!
        )

        XCTAssertEqual(saved.irisID, IrisID(account: "work", mailbox: "Drafts", uid: 43))
        let readCalls = await mail.calls
        XCTAssertEqual(readCalls, [.login, .examine("INBOX"), .fetchRawMessage(9), .logout])
        let markdown = "Looks good.\n\nOn 2026-10-24 13:42 CDT, Jane Doe wrote:\n> Can you look at the plan?"
        let expected = DraftMessage(
            from: me,
            to: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
            cc: [MailAddress(name: "Bob", address: "bob@example.com")],
            subject: "Re: Q4 plan",
            inReplyTo: "<m3@example.com>",
            references: ["<m1@example.com>", "<m3@example.com>"],
            markdown: markdown,
            html: MarkdownHTML.html(fromMarkdown: markdown)
        )
        let saveCalls = await client.calls
        XCTAssertEqual(saveCalls, [.login, .listMailboxes, .appendDraft(expected, "Drafts"), .logout])
    }

    func testSaveReplyToAMissingMessageNeverStartsTheSaveSession() async {
        let mail = inbox(holding: original, uid: 9)
        let client = FakeDraftClient(mailboxes: [drafts], appendedUID: 43)
        let missing = IrisID(account: "work", mailbox: "INBOX", uid: 10)

        await assertThrows(.unknownMessage(missing)) {
            try await self.writer(client, reading: mail).saveReply(
                to: missing, body: "Hi", from: self.me, replyAll: false, quote: true
            )
        }

        let saveCalls = await client.calls
        XCTAssertEqual(saveCalls, [])
    }
}
