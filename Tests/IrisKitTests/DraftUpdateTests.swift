import Foundation
import XCTest
import SwiftMail
@testable import IrisKit

final class DraftUpdateTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )
    private let mailbox = "[Gmail]/Entwürfe"
    private let wireMailbox = "[Gmail]/Entw&APw-rfe"
    private var originalID: IrisID { IrisID(account: "work", mailbox: mailbox, uid: 9) }
    private var replacementID: IrisID { IrisID(account: "work", mailbox: mailbox, uid: 43) }
    private let source = """
        From: Me <me@example.com>
        To: Jane <jane@example.com>
        Cc: Bob <bob@example.com>
        Bcc: Private <private@example.com>
        Reply-To: Replies <replies@example.com>
        Subject: Re: Plan
        Message-ID: <draft@example.com>
        In-Reply-To: <parent@example.com>
        References: <root@example.com> <parent@example.com>
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary=mix

        --mix
        Content-Type: multipart/alternative; boundary=alt

        --alt
        Content-Type: text/plain; charset=utf-8

        Old body and quote
        --alt
        Content-Type: text/html; charset=utf-8

        <p>Old body and quote<img src="cid:logo@example.com"></p>
        --alt--
        --mix
        Content-Type: application/pdf
        Content-Disposition: attachment; filename="plan.pdf"
        Content-Transfer-Encoding: base64

        JVBERg==
        --mix
        Content-Type: image/png
        Content-Disposition: inline; filename="logo.png"
        Content-ID: <logo@example.com>
        Content-Transfer-Encoding: base64

        AQID
        --mix--
        """

    private func fake(
        flags: [UInt32: [String]] = [9: [#"\Draft"#, #"\Seen"#]],
        capabilities: [String] = ["UIDPLUS"],
        uid: UInt32? = 43,
        errors: [FakeMailClient.Method: any Error] = [:],
        raw: Data? = nil
    ) -> FakeMailClient {
        FakeMailClient(
            capabilities: capabilities,
            statuses: [wireMailbox: MailboxStatus(messageCount: 3, uidValidity: 7, uidNext: 43)],
            rawMessages: [9: raw ?? Data(source.replacingOccurrences(of: "\n", with: "\r\n").utf8)],
            appendedUID: uid, flags: flags, errors: errors
        )
    }

    private func update(_ fake: FakeMailClient, id: IrisID? = nil) async throws -> SavedDraft {
        try await MailWriter(account: account, makeClient: { _ in fake }).updateDraft(id ?? originalID, body: "New **body**")
    }

    private func failure(_ fake: FakeMailClient, id: IrisID? = nil) async -> IrisError? {
        do {
            _ = try await update(fake, id: id)
            XCTFail("Expected update to fail")
            return nil
        } catch {
            return error as? IrisError
        }
    }

    func testReplacementPreservesHeadersAndAttachmentsAndRemovesOnlyOriginalAfterSave() async throws {
        // An unrelated deleted message is never named by STORE or UID EXPUNGE.
        let fake = fake(flags: [9: [#"\Draft"#], 11: [#"\Deleted"#]])
        let result = try await update(fake)
        XCTAssertEqual(result, SavedDraft(mailbox: mailbox, irisID: replacementID))
        let calls = await fake.calls
        let draft = try XCTUnwrap(calls.compactMap { call -> DraftMessage? in
            if case .appendDraft(let draft, _) = call { return draft }
            return nil
        }.first)
        XCTAssertEqual(draft.to.map(\.address), ["jane@example.com"])
        XCTAssertEqual(draft.cc.map(\.address), ["bob@example.com"])
        XCTAssertEqual(draft.bcc.map(\.address), ["private@example.com"])
        XCTAssertEqual(draft.replyTo.map(\.address), ["replies@example.com"])
        XCTAssertEqual(draft.subject, "Re: Plan")
        XCTAssertEqual(draft.inReplyTo, "<parent@example.com>")
        XCTAssertEqual(draft.references, ["<root@example.com>", "<parent@example.com>"])
        XCTAssertEqual(draft.markdown, "New **body**")
        XCTAssertEqual(draft.html, "<p>New <strong>body</strong></p>\n")
        XCTAssertEqual(draft.attachments.map(\.filename), ["plan.pdf", "logo.png"])
        XCTAssertEqual(draft.attachments.map(\.data), [Data("%PDF".utf8), Data([1, 2, 3])])
        XCTAssertEqual(draft.attachments.map(\.isInline), [false, true])
        XCTAssertEqual(draft.attachments.map(\.contentID), [nil, "logo@example.com"])
        XCTAssertEqual(calls, [
            .login, .select(wireMailbox), .fetchFlags(9), .capabilities, .fetchRawMessage(9),
            .appendDraft(draft, wireMailbox), .setDeleted(9), .expunge(9), .logout,
        ])
    }

    func testOrdinaryAndDeletedMessagesAreRejectedEvenInDraftsMailbox() async {
        for flags in [[#"\Seen"#], [#"\Draft"#, #"\Deleted"#]] {
            let fake = fake(flags: [9: flags])
            let error = await failure(fake)
            XCTAssertEqual(error, .notADraft(originalID))
            let calls = await fake.calls
            XCTAssertEqual(calls, [.login, .select(wireMailbox), .fetchFlags(9), .logout])
        }
    }

    func testSerializedReplacementRetainsBccThreadingAndInlineContent() throws {
        let raw = source.replacingOccurrences(
            of: "In-Reply-To: <parent@example.com>",
            with: "In-Reply-To: <parent@example.com> <other@example.com> (comment)"
        ).replacingOccurrences(of: "\n", with: "\r\n")
        let draft = try DraftUpdater.replacingBody(in: Data(raw.utf8), body: "New **body**")
        let serialized = Email(draft: draft).constructContent()
        let message = try EMLParser.parse(Data(serialized.utf8))
        XCTAssertEqual(message.header.bccAddresses.mailboxes.map(\.address), ["private@example.com"])
        XCTAssertEqual(message.header.replyToAddresses.mailboxes.map(\.address), ["replies@example.com"])
        XCTAssertEqual(message.header.messageId?.description, "<draft@example.com>")
        XCTAssertEqual(message.header.additionalFields?["in-reply-to"], "<parent@example.com> <other@example.com> (comment)")
        XCTAssertEqual(message.header.additionalFields?["references"], "<root@example.com> <parent@example.com>")
        XCTAssertTrue(message.textBody?.contains("New **body**") == true)
        XCTAssertTrue(message.htmlBody?.contains("<strong>body</strong>") == true)
        XCTAssertFalse(serialized.contains("Old body and quote"))
        let pdf = try XCTUnwrap(message.parts.first { $0.filename == "plan.pdf" })
        XCTAssertEqual(pdf.decodedData(), Data("%PDF".utf8))
        let logo = try XCTUnwrap(message.parts.first { $0.filename == "logo.png" })
        XCTAssertEqual(logo.decodedData(), Data([1, 2, 3]))
        XCTAssertEqual(logo.contentId, "logo@example.com")
        XCTAssertEqual(logo.disposition, "inline")
    }

    func testAnUnreferencedInlinePartWithoutDispositionIsPreserved() throws {
        let raw = source.replacingOccurrences(of: "Content-Disposition: inline; filename=\"logo.png\"\n", with: "")
            .replacingOccurrences(of: "<img src=\"cid:logo@example.com\">", with: "")
        let draft = try DraftUpdater.replacingBody(in: Data(raw.utf8), body: "New body")
        let logo = try XCTUnwrap(draft.attachments.first { $0.contentID == "logo@example.com" })
        XCTAssertTrue(logo.isInline)
        XCTAssertEqual(logo.data, Data([1, 2, 3]))
    }

    func testEmptyUnicodeNamedAttachmentSurvivesSerializedUpdate() throws {
        let raw = source.replacingOccurrences(of: "filename=\"plan.pdf\"", with: "filename*=UTF-8''R%C3%A9sum%C3%A9.pdf")
            .replacingOccurrences(of: "JVBERg==", with: "")
        let draft = try DraftUpdater.replacingBody(in: Data(raw.utf8), body: "New body")
        let serialized = Email(draft: draft).constructContent()
        let message = try EMLParser.parse(Data(serialized.utf8))
        let attachment = try XCTUnwrap(message.parts.first { $0.filename == "Résumé.pdf" })
        XCTAssertEqual(attachment.decodedData(), Data())
    }

    func testMissingSenderFailsBeforeSaving() async {
        let raw = source.replacingOccurrences(of: "From: Me <me@example.com>\n", with: "")
        let fake = fake(raw: Data(raw.utf8))
        let error = await failure(fake)
        guard case .draftNotPreserved = error else { return XCTFail("Expected preservation error") }
        let calls = await fake.calls
        XCTAssertEqual(calls.last, .logout)
        XCTAssertFalse(calls.contains { if case .appendDraft = $0 { return true }; return false })
    }

    func testRawDownloadTimeoutLeavesOriginalUntouched() async {
        let timeout = IrisError.messageDownloadTimedOut(seconds: 10)
        let fake = fake(errors: [.fetchRawMessage: timeout])
        let error = await failure(fake)
        XCTAssertEqual(error, timeout)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select(wireMailbox), .fetchFlags(9), .capabilities, .fetchRawMessage(9), .logout])
    }

    func testUnsupportedAttachmentMetadataFailsBeforeAppend() async {
        let raw = source.replacingOccurrences(of: "Content-Disposition: inline;", with: "Content-Disposition: attachment;")
        let fake = fake(raw: Data(raw.utf8))
        let error = await failure(fake)
        guard case .draftNotPreserved = error else { return XCTFail("Expected preservation error") }
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select(wireMailbox), .fetchFlags(9), .capabilities, .fetchRawMessage(9), .logout])
    }

    func testMissingUIDAndUIDZeroDoNotWrite() async {
        let fake = fake(flags: [:])
        let error = await failure(fake)
        XCTAssertEqual(error, .unknownMessage(originalID))
        let zero = IrisID(account: "work", mailbox: mailbox, uid: 0)
        let zeroFake = self.fake()
        let zeroError = await failure(zeroFake, id: zero)
        XCTAssertEqual(zeroError, .unknownMessage(zero))
        let calls = await zeroFake.calls
        XCTAssertEqual(calls, [])
    }

    func testNoUIDPlusFailsBeforeDownloadOrWrite() async {
        let fake = fake(capabilities: ["IMAP4rev1"])
        let error = await failure(fake)
        XCTAssertEqual(error, .draftUpdateNeedsUIDPlus(account: "work"))
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select(wireMailbox), .fetchFlags(9), .capabilities, .logout])
    }

    func testMissingAppendUIDNeverDeletesOriginal() async {
        for uid in [nil, UInt32(0), UInt32(9)] {
            let fake = fake(uid: uid)
            let error = await failure(fake)
            guard case .draftUpdateIncomplete(let original, let replacement, _) = error else {
                return XCTFail("Expected partial save error: \(String(describing: error))")
            }
            XCTAssertEqual(original, originalID)
            XCTAssertNil(replacement)
            let calls = await fake.calls
            XCTAssertFalse(calls.contains(.setDeleted(9)))
            XCTAssertFalse(calls.contains(.expunge(9)))
            XCTAssertEqual(calls.last, .logout)
        }
    }

    func testRefusedAndUncertainAppendNeverDeleteOriginal() async {
        let cases: [(IrisError, IrisError)] = [
            (.draftRefused(account: "work", mailbox: wireMailbox, reason: "NO"),
             .draftRefused(account: "work", mailbox: mailbox, reason: "NO")),
            (.draftMayBeSaved(account: "work", mailbox: wireMailbox, reason: "timeout"),
             .draftUpdateMayBeSaved(original: originalID, reason: "timeout")),
        ]
        for (thrown, expected) in cases {
            let fake = fake(errors: [.appendDraft: thrown])
            let error = await failure(fake)
            XCTAssertEqual(error, expected)
            let calls = await fake.calls
            XCTAssertFalse(calls.contains(.setDeleted(9)))
            XCTAssertFalse(calls.contains(.expunge(9)))
            XCTAssertEqual(calls.last, .logout)
        }
    }

    func testCleanupFailuresNameBothIDsRedactSecretsAndDoNotRollbackReplacement() async {
        for method in [FakeMailClient.Method.setDeleted, .expunge] {
            let fake = fake(errors: [method: IrisError.serverError(account: "work", command: "STORE", reason: "secret refused")])
            let error = await failure(fake)
            guard case .draftUpdateIncomplete(let original, let replacement, let reason) = error else {
                return XCTFail("Expected partial save error")
            }
            XCTAssertEqual(original, originalID)
            XCTAssertEqual(replacement, replacementID)
            XCTAssertFalse(reason.contains("secret"))
            XCTAssertTrue(error?.localizedDescription.contains(originalID.description) == true)
            XCTAssertTrue(error?.localizedDescription.contains(replacementID.description) == true)
            let calls = await fake.calls
            XCTAssertFalse(calls.contains(.setDeleted(43)))
            XCTAssertFalse(calls.contains(.expunge(43)))
            if method == .setDeleted { XCTAssertFalse(calls.contains(.expunge(9))) }
            XCTAssertEqual(calls.last, .logout)
        }
    }
}
