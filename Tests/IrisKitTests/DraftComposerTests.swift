import Foundation
import SwiftMail
import XCTest
@testable import IrisKit

final class DraftComposerTests: XCTestCase {
    private let from = MailAddress(name: "Me", address: "me@example.com")

    func testNewDraftHasRecipientsBodyAndAttachmentsWithoutReplyHeaders() throws {
        let files = [DraftAttachment(filename: "plan.txt", mimeType: "text/plain", data: Data("plan".utf8))]
        let draft = try DraftComposer.new(
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
        let draft = try DraftComposer.new(
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
        XCTAssertThrowsError(try DraftComposer.new(from: from, to: [], subject: "Hello", body: "Body")) {
            XCTAssertEqual($0 as? IrisError, .draftRecipientsMissing)
        }
    }

    func testSerializedNewDraftKeepsBccAndBothBodiesWithoutThreading() throws {
        let draft = try DraftComposer.new(
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
                XCTAssertThrowsError(try DraftComposer.new(
                    from: from, to: option == "--to" ? [value] : ["a@example.com"],
                    cc: option == "--cc" ? [value] : [], bcc: option == "--bcc" ? [value] : [],
                    subject: "Hello", body: "Body"
                ), "\(option): \(value)") {
                    XCTAssertEqual($0 as? IrisError, .draftRecipientInvalid(option: option))
                }
            }
        }
    }

    func testRejectsEmptyOrMultilineSubjects() {
        for subject in ["", " \t", "Hello\r\nBcc: b@example.com", "Hello\nworld", "Hello\0world"] {
            XCTAssertThrowsError(try DraftComposer.new(from: from, to: ["a@example.com"], subject: subject, body: "Body")) {
                XCTAssertEqual($0 as? IrisError, .draftSubjectInvalid)
            }
        }
    }

    func testNewDraftSavesInOneSessionWithoutReadingAMessage() async throws {
        let draft = try DraftComposer.new(from: from, to: ["jane@example.com"], subject: "Hello", body: "Body")
        let fake = FakeMailClient(mailboxes: [MailboxInfo(name: "Drafts", attributes: [#"\Drafts"#])], appendedUID: 42)
        let account = Account(name: "work", host: "imap.example.com", port: 993, username: from.address, authentication: .password("secret"))
        let saved = try await MailWriter(account: account, makeClient: { _ in fake }).saveDraft(draft)
        XCTAssertEqual(saved.irisID, IrisID(account: "work", mailbox: "Drafts", uid: 42))
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .appendDraft(draft, "Drafts"), .logout])
    }
}
