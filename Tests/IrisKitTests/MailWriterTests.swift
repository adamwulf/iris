import Foundation
import XCTest
@testable import IrisKit

final class MailWriterTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )

    private func writer(_ fake: FakeMailClient) -> MailWriter {
        MailWriter(account: account, makeClient: { _ in fake })
    }

    /// The iris ID of `uid` in `mailbox` of the test account.
    private func id(_ uid: UInt32, in mailbox: String = "INBOX") -> IrisID {
        IrisID(account: account.name, mailbox: mailbox, uid: uid)
    }

    private func assertThrows(
        _ expected: IrisError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected), but nothing was thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? IrisError, expected, file: file, line: line)
        }
    }

    // MARK: - read and unread

    func testMarkReadSelectsTheMailboxFindsTheMessageAndAddsSeen() async throws {
        let fake = FakeMailClient.inbox(count: 3)

        try await writer(fake).markRead(id(102))

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([102]), .setSeen(true, 102), .logout])
    }

    func testMarkUnreadSelectsTheMailboxFindsTheMessageAndRemovesSeen() async throws {
        let fake = FakeMailClient.inbox(count: 3)

        try await writer(fake).markUnread(id(102))

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([102]), .setSeen(false, 102), .logout])
    }

    func testTheStoreDoesNotDependOnTheCurrentFlag() async throws {
        // Not a toggle: read always adds \Seen and unread always removes it, so
        // running either one twice gives the same result.
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 2, uidValidity: 7, uidNext: 200)],
            envelopes: [
                FakeMailClient.envelope(sequenceNumber: 1, seen: true),
                FakeMailClient.envelope(sequenceNumber: 2, seen: false),
            ]
        )

        try await writer(fake).markRead(id(101))
        try await writer(fake).markUnread(id(102))

        let stores = await fake.calls.filter {
            if case .setSeen = $0 { return true }
            return false
        }
        XCTAssertEqual(stores, [.setSeen(true, 101), .setSeen(false, 102)])
    }

    func testSelectsTheModifiedUTF7Name() async throws {
        let fake = FakeMailClient(
            statuses: ["[Gmail]/Entw&APw-rfe": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [FakeMailClient.envelope(sequenceNumber: 1)]
        )

        try await writer(fake).markRead(id(101, in: "[Gmail]/Entwürfe"))

        let calls = await fake.calls
        XCTAssertEqual(calls, [
            .login, .select("[Gmail]/Entw&APw-rfe"), .fetchEnvelopesByUID([101]), .setSeen(true, 101), .logout,
        ])
    }

    // MARK: - errors

    func testMissingMessageThrowsUnknownMessageAndChangesNothing() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMessage(id(999))) { try await self.writer(fake).markRead(self.id(999)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([999]), .logout])
    }

    func testUIDZeroIsRejectedBeforeConnecting() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMessage(id(0))) { try await self.writer(fake).markUnread(self.id(0)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testUnknownMailboxErrorHasTheNameTheUserTypedNotTheWireName() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMailbox(account: "work", name: "R&D", reason: "NO no such mailbox")) {
            try await self.writer(fake).markRead(self.id(101, in: "R&D"))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("R&-D"), .logout])
    }

    func testFailedStoreStillLogsOut() async {
        let failure = IrisError.serverError(account: "work", command: "STORE", reason: "Store failed: NO read-only")
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [FakeMailClient.envelope(sequenceNumber: 1)],
            errors: [.setSeen: failure]
        )

        await assertThrows(failure) { try await self.writer(fake).markRead(self.id(101)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([101]), .setSeen(true, 101), .logout])
    }

    func testFailedLoginStillLogsOutAndDoesNothingElse() async {
        let failure = IrisError.loginFailed(
            account: "work", username: "me@example.com", host: "imap.example.com", reason: "NO invalid credentials"
        )
        let fake = FakeMailClient(errors: [.login: failure])

        await assertThrows(failure) { try await self.writer(fake).markRead(self.id(101)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .logout])
    }

    // MARK: - drafts

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
            html: "<p>Looks good.</p>\n",
            attachments: []
        )
    }

    func testSaveDraftAppendsToTheDraftsMailboxAndGivesTheIrisID() async throws {
        let fake = FakeMailClient(
            mailboxes: [MailboxInfo(name: "INBOX", attributes: []), drafts, MailboxInfo(name: "Sent", attributes: [#"\Sent"#])],
            appendedUID: 42
        )

        let saved = try await writer(fake).saveDraft(draft)

        XCTAssertEqual(saved, SavedDraft(mailbox: "Drafts", irisID: id(42, in: "Drafts")))
        XCTAssertNil(saved.missingIDNote)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "Drafts"), .logout])
    }

    /// LIST gives wire names, and the attributes can come in a second entry for the name.
    func testSaveDraftAppendsToTheWireNameAndGivesTheDecodedNameInTheIrisID() async throws {
        let fake = FakeMailClient(
            mailboxes: [
                MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: []),
                MailboxInfo(name: "INBOX", attributes: []),
                MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: [#"\Drafts"#]),
            ],
            appendedUID: 7
        )

        let saved = try await writer(fake).saveDraft(draft)

        XCTAssertEqual(saved.mailbox, "[Gmail]/Entwürfe")
        XCTAssertEqual(saved.irisID?.description, "work/[Gmail]/Entwürfe/7")
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "[Gmail]/Entw&APw-rfe"), .logout])
    }

    func testSaveDraftWithoutAUIDFromTheServerHasNoIrisIDAndANote() async throws {
        let fake = FakeMailClient(mailboxes: [drafts], appendedUID: nil)

        let saved = try await writer(fake).saveDraft(draft)

        XCTAssertEqual(saved, SavedDraft(mailbox: "Drafts", irisID: nil))
        XCTAssertEqual(
            saved.missingIDNote,
            "The draft was saved in \"Drafts\", but the server did not report its UID, so iris cannot give its iris ID."
        )
    }

    func testSaveDraftWithoutADraftsMailboxThrowsAndLogsOut() async {
        let fake = FakeMailClient(mailboxes: [MailboxInfo(name: "INBOX", attributes: []), MailboxInfo(name: "Drafts", attributes: [])])

        await assertThrows(.draftsMailboxNotFound(account: "work")) { _ = try await self.writer(fake).saveDraft(self.draft) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .logout], "a mailbox named Drafts without the attribute is not used")
    }

    func testSaveDraftAfterAFailedLoginStillLogsOutAndSavesNothing() async {
        let failure = IrisError.loginFailed(account: "work", username: "me@example.com", host: "imap.example.com", reason: "NO")
        let fake = FakeMailClient(mailboxes: [drafts], errors: [.login: failure])

        await assertThrows(failure) { _ = try await self.writer(fake).saveDraft(self.draft) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .logout])
    }

    func testSaveDraftAfterAFailedListStillLogsOut() async {
        let failure = IrisError.serverError(account: "work", command: "LIST", reason: "NO")
        let fake = FakeMailClient(mailboxes: [drafts], errors: [.listMailboxes: failure])

        await assertThrows(failure) { _ = try await self.writer(fake).saveDraft(self.draft) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .logout])
    }

    func testFailedAppendStillLogsOut() async {
        let failure = IrisError.draftTooLarge(account: "work", size: 2000, limit: 1000)
        let fake = FakeMailClient(mailboxes: [drafts], errors: [.appendDraft: failure])

        await assertThrows(failure) { _ = try await self.writer(fake).saveDraft(self.draft) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "Drafts"), .logout])
    }

    func testDraftMayBeSavedGetsTheDecodedMailboxNameAndLogsOut() async {
        let fake = FakeMailClient(
            mailboxes: [MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: [#"\Drafts"#])],
            errors: [.appendDraft: IrisError.draftMayBeSaved(account: "work", mailbox: "[Gmail]/Entw&APw-rfe", reason: "timeout")]
        )

        await assertThrows(.draftMayBeSaved(account: "work", mailbox: "[Gmail]/Entwürfe", reason: "timeout")) {
            _ = try await self.writer(fake).saveDraft(self.draft)
        }

        let calls = await fake.calls
        XCTAssertEqual(calls.last, .logout)
    }

    func testDraftRefusedGetsTheDecodedMailboxNameAndLogsOut() async {
        let fake = FakeMailClient(
            mailboxes: [MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: [#"\Drafts"#])],
            errors: [.appendDraft: IrisError.draftRefused(account: "work", mailbox: "[Gmail]/Entw&APw-rfe", reason: "NO")]
        )

        await assertThrows(.draftRefused(account: "work", mailbox: "[Gmail]/Entwürfe", reason: "NO")) {
            _ = try await self.writer(fake).saveDraft(self.draft)
        }

        let calls = await fake.calls
        XCTAssertEqual(calls.last, .logout)
    }

    private let original = """
        From: Jane Doe <jane@example.com>
        To: Me <me@example.com>, Bob <bob@example.com>
        Subject: Q4 plan
        Date: Sat, 24 Oct 2026 13:42:00 -0500
        Message-ID: <m3@example.com>
        References: <m1@example.com>

        Can you look at the plan?
        """

    /// A fake whose INBOX holds `text` at `uid`, and whose `\Drafts` mailbox gives new drafts UID 43.
    private func server(holding text: String, uid: UInt32) -> FakeMailClient {
        FakeMailClient(
            mailboxes: [MailboxInfo(name: "INBOX", attributes: []), drafts],
            statuses: ["INBOX": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: uid + 1)],
            rawMessages: [uid: Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)],
            appendedUID: 43
        )
    }

    func testSaveReplyReadsTheOriginalThenSavesTheReplyInASecondSession() async throws {
        let fake = server(holding: original, uid: 9)

        let saved = try await writer(fake).saveReply(
            to: id(9),
            body: "Looks good.",
            from: me,
            replyAll: true,
            quote: true,
            timeZone: TimeZone(identifier: "America/Chicago")!
        )

        XCTAssertEqual(saved.irisID, id(43, in: "Drafts"))
        let markdown = "Looks good.\n\nOn 2026-10-24 13:42 CDT, Jane Doe wrote:\n> Can you look at the plan?"
        let expected = DraftMessage(
            from: me,
            to: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
            cc: [MailAddress(name: "Bob", address: "bob@example.com")],
            subject: "Re: Q4 plan",
            inReplyTo: "<m3@example.com>",
            references: ["<m1@example.com>", "<m3@example.com>"],
            markdown: markdown,
            // The original is text/plain, so the quote is its text, escaped.
            html: "<p>Looks good.</p>\n<p>On 2026-10-24 13:42 CDT, Jane Doe wrote:</p>\n"
                + "<blockquote type=\"cite\">\nCan you look at the plan?\n</blockquote>\n",
            attachments: []
        )
        let calls = await fake.calls
        XCTAssertEqual(calls, [
            // Reading: EXAMINE, the size, and BODY.PEEK[], so the original stays unread.
            .login, .examine("INBOX"), .fetchOutline(9), .fetchRawMessage(9), .logout,
            .login, .listMailboxes, .appendDraft(expected, "Drafts"), .logout,
        ])
    }

    func testSaveReplyAppendsTheDraftWithItsAttachments() async throws {
        let fake = server(holding: original, uid: 9)
        let files = [
            DraftAttachment(filename: "plan.pdf", mimeType: "application/pdf", data: Data("%PDF".utf8)),
            DraftAttachment(filename: "empty.txt", mimeType: "text/plain", data: Data()),
        ]

        let saved = try await writer(fake).saveReply(
            to: id(9), body: "See the files.", from: me, replyAll: false, quote: false, attachments: files
        )

        XCTAssertEqual(saved.irisID, id(43, in: "Drafts"))
        let calls = await fake.calls
        let appended = calls.compactMap { call -> DraftMessage? in
            guard case .appendDraft(let draft, "Drafts") = call else {
                return nil
            }
            return draft
        }
        XCTAssertEqual(appended.map(\.attachments), [files], "one APPEND, with the files in order")
        XCTAssertEqual(appended.first?.markdown, "See the files.")
    }

    func testSaveReplyToAMissingMessageNeverStartsTheSaveSession() async {
        let fake = server(holding: original, uid: 9)

        await assertThrows(.unknownMessage(id(10))) {
            _ = try await self.writer(fake).saveReply(to: self.id(10), body: "Hi", from: self.me, replyAll: false, quote: true)
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchOutline(10), .logout])
    }

    /// A 20 MB original: its header fields and body come from the outline and
    /// its one body part, and its attachment stays on the server.
    func testSaveReplyQuotesALargeOriginalFromItsBodyPart() async throws {
        let part = AttachmentID(components: [1])
        let fake = FakeMailClient(
            mailboxes: [MailboxInfo(name: "INBOX", attributes: []), drafts],
            statuses: ["INBOX": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 10)],
            outlines: [9: MessageOutline(
                size: 20_000_000,
                headers: MessageHeaders(
                    messageID: "<m3@example.com>",
                    subject: "Q4 plan",
                    from: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
                    to: [MailAddress(name: "Me", address: "me@example.com"), MailAddress(name: "Bob", address: "bob@example.com")],
                    date: ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z"),
                    references: ["<m1@example.com>"]
                ),
                parts: [
                    PartOutline(id: part, contentType: "text/plain; charset=utf-8", encoding: "7BIT", size: 25),
                    PartOutline(
                        id: AttachmentID(components: [2]), contentType: "application/pdf", disposition: "attachment",
                        encoding: "BASE64", filename: "plan.pdf", size: 27_000_000
                    ),
                ]
            )],
            parts: [9: [part: Data("Can you look at the plan?".utf8)]],
            appendedUID: 43
        )

        let saved = try await writer(fake).saveReply(
            to: id(9),
            body: "Looks good.",
            from: me,
            replyAll: true,
            quote: true,
            timeZone: TimeZone(identifier: "America/Chicago")!
        )

        XCTAssertEqual(saved.irisID, id(43, in: "Drafts"))
        let expected = DraftMessage(
            from: me,
            to: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
            cc: [MailAddress(name: "Bob", address: "bob@example.com")],
            subject: "Re: Q4 plan",
            inReplyTo: "<m3@example.com>",
            references: ["<m1@example.com>", "<m3@example.com>"],
            markdown: "Looks good.\n\nOn 2026-10-24 13:42 CDT, Jane Doe wrote:\n> Can you look at the plan?",
            html: "<p>Looks good.</p>\n<p>On 2026-10-24 13:42 CDT, Jane Doe wrote:</p>\n"
                + "<blockquote type=\"cite\">\nCan you look at the plan?\n</blockquote>\n",
            attachments: []
        )
        let calls = await fake.calls
        XCTAssertEqual(calls, [
            // Reading: EXAMINE, the outline, and BODY.PEEK[1]: never the whole message or the PDF.
            .login, .examine("INBOX"), .fetchOutline(9), .fetchBodyPart(part, 9), .logout,
            .login, .listMailboxes, .appendDraft(expected, "Drafts"), .logout,
        ])
    }
}
