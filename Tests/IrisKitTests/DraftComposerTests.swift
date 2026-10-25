import Foundation
import SwiftMail
import XCTest
@testable import IrisKit

final class DraftComposerTests: XCTestCase {
    private let from = MailAddress(name: "Me", address: "me@example.com")

    private func newDraft(
        from: MailAddress, to: [String], cc: [String] = [], bcc: [String] = [],
        subject: String, body: String, attachments: [DraftAttachment] = []
    ) throws -> DraftMessage {
        try DraftComposer(from: from, to: to, cc: cc, bcc: bcc, subject: subject)
            .message(body: body, attachments: attachments)
    }

    func testHeadersAcceptUnicodeFormattingCharactersAndSerializeNamesSafely() throws {
        let name = "می\u{200C}خواهم"
        let draft = try newDraft(
            from: from, to: ["Doe, Jane <jane@example.com>"],
            cc: ["\(name) <cc@example.com>"], bcc: ["Doe, Jane <hidden@example.com>", "José <jose@example.com>"],
            subject: "👩‍💻 Dev sync", body: "Hello"
        )
        XCTAssertEqual(draft.subject, "👩‍💻 Dev sync")
        XCTAssertEqual(draft.cc.first?.name, name)
        let content = Email(draft: draft).constructContent(use8BitMIME: true)
        XCTAssertTrue(content.contains("To: \"Doe, Jane\" <jane@example.com>\r\n"), content)
        XCTAssertTrue(content.contains("Bcc: \"Doe, Jane\" <hidden@example.com>, =?UTF-8?"), content)
        XCTAssertTrue(content.contains("Cc: =?UTF-8?"), content)
        XCTAssertTrue(content.contains("Subject: =?UTF-8?"), content)
        // Decode what SwiftMail wrote, so the assertions cover the encoded names too.
        let parsed = try EMLParser.parse(Data(content.utf8))
        let headers = MessageDecoder.headers(of: parsed, rawMessage: Data(content.utf8))
        XCTAssertEqual(headers.to, draft.to)
        XCTAssertEqual(headers.cc, draft.cc)
        XCTAssertEqual(MessageDecoder.addresses(parsed.header.bccAddresses), draft.bcc)
        XCTAssertEqual(headers.subject, draft.subject)
    }

    func testNewDraftHasRecipientsBodyAndAttachmentsWithoutReplyHeaders() throws {
        let files = [DraftAttachment(filename: "plan.txt", mimeType: "text/plain", data: Data("plan".utf8))]
        let draft = try newDraft(
            from: from, to: ["\"Doe, Jane\" <jane@example.com>", "bob@example.com"],
            cc: ["José <jose@example.com>"], bcc: ["private@example.com"],
            subject: "Café plans", body: "Hello **everyone**!\r\nNext line.", attachments: files
        )
        XCTAssertEqual(draft.from, from)
        XCTAssertEqual(draft.to, [
            MailAddress(name: "Doe, Jane", address: "jane@example.com"),
            MailAddress(name: nil, address: "bob@example.com"),
        ])
        XCTAssertEqual(draft.cc, [MailAddress(name: "José", address: "jose@example.com")])
        XCTAssertEqual(draft.bcc, [MailAddress(name: nil, address: "private@example.com")])
        XCTAssertEqual(draft.subject, "Café plans")
        XCTAssertEqual(draft.markdown, "Hello **everyone**!\nNext line.")
        XCTAssertTrue(draft.html.contains("<strong>everyone</strong>"), draft.html)
        XCTAssertFalse(draft.html.contains("<blockquote"))
        XCTAssertNil(draft.messageID)
        XCTAssertNil(draft.inReplyTo)
        XCTAssertEqual(draft.references, [])
        XCTAssertEqual(draft.threadingHeaders, [:])
        XCTAssertEqual(draft.replyTo, [])
        XCTAssertEqual(draft.attachments, files)
    }

    func testNewDraftUsesTheSafeMarkdownRenderer() throws {
        let draft = try newDraft(
            from: from, to: ["jane@example.com"], subject: "Hello",
            body: "<script>alert('hello')</script>"
        )
        XCTAssertFalse(draft.html.contains("<script>"))
        XCTAssertTrue(draft.html.contains("&lt;script&gt;"))
        XCTAssertEqual(draft.cc, [])
        XCTAssertEqual(draft.bcc, [])
        XCTAssertEqual(draft.attachments, [])
    }

    func testRequiresAToRecipient() {
        XCTAssertThrowsError(try newDraft(from: from, to: [], subject: "Hello", body: "Body")) {
            XCTAssertEqual($0 as? IrisError, .draftRecipientsMissing)
        }
    }

    func testSerializedNewDraftKeepsBccAndBothBodiesWithoutThreading() throws {
        let draft = try newDraft(
            from: from, to: ["jane@example.com"], cc: ["cc@example.com"],
            bcc: ["Hidden <hidden@example.com>", "other@example.com"], subject: "New conversation",
            body: "Hello **Jane**.",
            attachments: [DraftAttachment(filename: "note.txt", mimeType: "text/plain", data: Data("note".utf8))]
        )
        let content = Email(draft: draft).constructContent(use8BitMIME: true)
        XCTAssertTrue(content.contains("To: jane@example.com\r\n"), content)
        XCTAssertTrue(content.contains("Cc: cc@example.com\r\n"), content)
        XCTAssertTrue(content.contains("Bcc: Hidden <hidden@example.com>, other@example.com\r\n"), content)
        XCTAssertTrue(content.contains("Subject: New conversation\r\n"), content)
        XCTAssertTrue(content.contains("Message-Id: <"), content)
        XCTAssertTrue(content.contains("multipart/mixed"), content)
        XCTAssertTrue(content.contains("multipart/alternative"), content)
        XCTAssertTrue(content.contains("Hello **Jane**."), content)
        XCTAssertTrue(content.contains("<strong>Jane</strong>"), content)
        XCTAssertTrue(content.contains("filename=\"note.txt\""), content)
        XCTAssertFalse(content.contains("In-Reply-To:"), content)
        XCTAssertFalse(content.contains("References:"), content)
    }

    func testRejectsInvalidRecipientsInEachHeader() {
        for value in ["", "not an address", "user@", "@example.com", "a@example.com, b@example.com", "a@example.com\r\nBcc: b@example.com"] {
            for option in ["--to", "--cc", "--bcc"] {
                XCTAssertThrowsError(try newDraft(
                    from: from, to: option == "--to" ? [value] : ["a@example.com"],
                    cc: option == "--cc" ? [value] : [], bcc: option == "--bcc" ? [value] : [],
                    subject: "Hello", body: "Body"
                ), "\(option): \(value)") {
                    XCTAssertEqual($0 as? IrisError, .draftRecipientInvalid(option: option, value: value))
                }
            }
        }
    }

    func testRejectsEmptyOrMultilineSubjects() {
        for subject in ["", " \t", "Hello\r\nBcc: b@example.com", "Hello\nworld", "Hello\0world"] {
            XCTAssertThrowsError(try newDraft(from: from, to: ["a@example.com"], subject: subject, body: "Body")) {
                XCTAssertEqual($0 as? IrisError, .draftSubjectInvalid)
            }
        }
    }

    func testNewDraftSavesInOneSessionWithoutReadingAMessage() async throws {
        let draft = try newDraft(from: from, to: ["jane@example.com"], subject: "Hello", body: "Body")
        let fake = FakeMailClient(mailboxes: [MailboxInfo(name: "Drafts", attributes: [#"\Drafts"#])], appendedUID: 42)
        let account = Account(name: "work", host: "imap.example.com", port: 993, username: from.address, authentication: .password("secret"))
        let saved = try await MailWriter(account: account, makeClient: { _ in fake }).saveDraft(draft)
        XCTAssertEqual(saved.irisID, IrisID(account: "work", mailbox: "Drafts", uid: 42))
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "Drafts"), .logout])
    }
}
