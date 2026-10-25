import Foundation
import XCTest
@testable import IrisKit

final class ReplyComposerTests: XCTestCase {
    private let me = MailAddress(name: "Adam", address: "adam@example.com")
    private let jane = MailAddress(name: "Jane Doe", address: "jane@example.com")
    private let chicago = TimeZone(identifier: "America/Chicago")!
    /// 2026-10-24 13:42 CDT.
    private let sent = Date(timeIntervalSince1970: 1_792_867_320)

    private func original(
        messageID: String? = "<m3@example.com>",
        subject: String? = "Q4 plan",
        from: [MailAddress]? = nil,
        to: [MailAddress]? = nil,
        cc: [MailAddress] = [],
        replyTo: [MailAddress] = [],
        date: Date? = nil,
        inReplyTo: String? = nil,
        references: [String] = [],
        body: String = "Can you look at the plan?"
    ) -> MessageDocument {
        MessageDocument(
            messageID: messageID,
            subject: subject,
            from: from ?? [jane],
            to: to ?? [me],
            cc: cc,
            replyTo: replyTo,
            date: date ?? sent,
            inReplyTo: inReplyTo,
            references: references,
            body: body,
            bodySource: .text,
            attachments: []
        )
    }

    private func reply(
        to original: MessageDocument,
        body: String = "Looks good.",
        username: String = "adam@example.com",
        replyAll: Bool = false,
        quote: Bool = true
    ) -> DraftMessage {
        ReplyComposer.reply(
            to: original, body: body, from: me, username: username, replyAll: replyAll, quote: quote, timeZone: chicago
        )
    }

    // MARK: - Recipients

    func testTheReplyGoesToTheSenderFromMe() {
        let draft = reply(to: original())
        XCTAssertEqual(draft.from, me)
        XCTAssertEqual(draft.to, [jane])
        XCTAssertEqual(draft.cc, [])
    }

    func testTheReplyGoesToReplyToWhenTheOriginalHasIt() {
        let list = MailAddress(name: "Team", address: "team@example.com")
        XCTAssertEqual(reply(to: original(replyTo: [list])).to, [list])
    }

    func testWithoutAllTheOtherRecipientsAreLeftOut() {
        let bob = MailAddress(name: "Bob", address: "bob@example.com")
        XCTAssertEqual(reply(to: original(to: [me, bob], cc: [bob])).cc, [])
    }

    func testAllCcsTheOtherRecipientsWithoutTheSenderMeOrRepeats() {
        let bob = MailAddress(name: "Bob", address: "bob@example.com")
        let carol = MailAddress(name: nil, address: "carol@example.com")
        let draft = reply(
            to: original(
                to: [MailAddress(name: "Adam W", address: "ADAM@example.com"), bob, jane],
                cc: [MailAddress(name: "Robert", address: "Bob@Example.com"), carol]
            ),
            replyAll: true
        )
        XCTAssertEqual(draft.to, [jane])
        XCTAssertEqual(draft.cc, [bob, carol], "addresses are compared ignoring case; the first copy wins")
    }

    func testAllLeavesOutTheUsernameWhenItIsAnAddress() {
        let bob = MailAddress(name: "Bob", address: "bob@example.com")
        let login = MailAddress(name: nil, address: "login@example.com")
        let draft = reply(to: original(to: [login, bob]), username: "login@example.com", replyAll: true)
        XCTAssertEqual(draft.cc, [bob])
    }

    func testAllKeepsARecipientThatMatchesAUsernameThatIsNotAnAddress() {
        let local = MailAddress(name: nil, address: "adam")
        let draft = reply(to: original(to: [local]), username: "adam", replyAll: true)
        XCTAssertEqual(draft.cc, [local], "only a username with an @ is an address")
    }

    func testAllLeavesOutTheReplyToAddresses() {
        let list = MailAddress(name: "Team", address: "team@example.com")
        let draft = reply(to: original(to: [list, jane], replyTo: [list]), replyAll: true)
        XCTAssertEqual(draft.to, [list])
        XCTAssertEqual(draft.cc, [jane], "the sender is Cc'd when the reply goes to Reply-To")
    }

    // MARK: - Subject

    func testSubjectGetsOneRe() {
        XCTAssertEqual(ReplyComposer.subject(replyingTo: "Q4 plan"), "Re: Q4 plan")
        XCTAssertEqual(ReplyComposer.subject(replyingTo: "Re: Q4 plan"), "Re: Q4 plan")
        XCTAssertEqual(ReplyComposer.subject(replyingTo: "RE: Q4 plan"), "RE: Q4 plan")
        XCTAssertEqual(ReplyComposer.subject(replyingTo: "re:Q4 plan"), "re:Q4 plan")
        XCTAssertEqual(ReplyComposer.subject(replyingTo: "  Q4 plan "), "Re: Q4 plan")
        XCTAssertEqual(ReplyComposer.subject(replyingTo: "Fwd: Q4 plan"), "Re: Fwd: Q4 plan")
    }

    func testSubjectWithoutAnOriginalSubjectIsJustRe() {
        XCTAssertEqual(ReplyComposer.subject(replyingTo: nil), "Re:")
        XCTAssertEqual(ReplyComposer.subject(replyingTo: " "), "Re:")
        XCTAssertEqual(reply(to: original(subject: nil)).subject, "Re:")
    }

    // MARK: - Threading

    func testThreadingAddsTheMessageIDToTheReferences() {
        let draft = reply(to: original(inReplyTo: "<m2@example.com>", references: ["<m1@example.com>", "<m2@example.com>"]))
        XCTAssertEqual(draft.inReplyTo, "<m3@example.com>")
        XCTAssertEqual(draft.references, ["<m1@example.com>", "<m2@example.com>", "<m3@example.com>"])
    }

    func testThreadingUsesInReplyToWhenThereAreNoReferences() {
        let draft = reply(to: original(inReplyTo: "<m2@example.com>"))
        XCTAssertEqual(draft.references, ["<m2@example.com>", "<m3@example.com>"])
    }

    func testThreadingOfAFirstMessageIsItsMessageID() {
        let draft = reply(to: original())
        XCTAssertEqual(draft.inReplyTo, "<m3@example.com>")
        XCTAssertEqual(draft.references, ["<m3@example.com>"])
    }

    func testThreadingIsLeftOutWithoutAMessageID() {
        let draft = reply(to: original(messageID: nil, inReplyTo: "<m2@example.com>", references: ["<m1@example.com>"]))
        XCTAssertNil(draft.inReplyTo)
        XCTAssertEqual(draft.references, [])
        XCTAssertEqual(draft.threadingHeaders, [:])
    }

    /// iris writes these headers as they are, so an ID must not be able to break a header line.
    func testThreadingLeavesOutIDsWithWhiteSpaceOrControlCharacters() {
        let draft = reply(to: original(references: ["<a@example.com>", "<b\r\nBcc: x@example.com>", "<c d@example.com>"]))
        XCTAssertEqual(draft.references, ["<a@example.com>", "<m3@example.com>"])

        let broken = reply(to: original(messageID: "<m3@example.com>\r\nBcc: x@example.com"))
        XCTAssertNil(broken.inReplyTo)
        XCTAssertEqual(broken.references, [])
    }

    func testThreadingHeadersHoldInReplyToAndReferences() {
        let draft = reply(to: original(references: ["<m1@example.com>"]))
        XCTAssertEqual(draft.threadingHeaders, [
            "In-Reply-To": "<m3@example.com>",
            "References": "<m1@example.com> <m3@example.com>",
        ])
    }

    func testALongReferencesHeaderIsFoldedBetweenIDs() throws {
        let ids = (1...8).map { "<message-\($0)-0123456789@mail.example.com>" }
        let value = DraftMessage.folded(ids, headerName: "References")

        let lines = ("References: " + value).components(separatedBy: "\r\n")
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines {
            XCTAssertLessThanOrEqual(line.utf8.count, DraftMessage.maxLineLength, line)
        }
        for line in lines.dropFirst() {
            XCTAssertTrue(line.hasPrefix(" <"), "a folded line starts with a space: \(line)")
        }
        // Unfolding (RFC 5322, section 2.2.3) gives the IDs back with one space between them.
        XCTAssertEqual(value.replacingOccurrences(of: "\r\n", with: ""), ids.joined(separator: " "))
    }

    func testAShortReferencesHeaderIsNotFoldedAndALongIDStaysWhole() {
        XCTAssertEqual(DraftMessage.folded(["<a@x>", "<b@x>"], headerName: "References"), "<a@x> <b@x>")
        let long = "<" + String(repeating: "x", count: 90) + "@example.com>"
        XCTAssertEqual(DraftMessage.folded([long, "<b@x>"], headerName: "References"), long + "\r\n <b@x>")
        XCTAssertEqual(DraftMessage.folded([], headerName: "References"), "")
    }

    // MARK: - Body and quote

    func testTheQuoteFollowsTheReplyWithTheDateAndTheSender() {
        let draft = reply(to: original(body: "Can you look?\n\nThe plan is attached.\n> Earlier quote"))
        XCTAssertEqual(
            draft.markdown,
            """
            Looks good.

            On 2026-10-24 13:42 CDT, Jane Doe wrote:
            > Can you look?
            >
            > The plan is attached.
            > > Earlier quote
            """
        )
    }

    func testTheQuoteNamesTheAddressWhenTheSenderHasNoName() {
        let draft = reply(to: original(from: [MailAddress(name: nil, address: "jane@example.com")]))
        XCTAssertTrue(draft.markdown.contains("\n\nOn 2026-10-24 13:42 CDT, jane@example.com wrote:\n> Can you"), draft.markdown)
    }

    func testTheQuoteWithoutADateNamesOnlyTheSender() {
        let undated = MessageDocument(
            messageID: nil, subject: nil, from: [jane], to: [me], cc: [], replyTo: [], date: nil,
            inReplyTo: nil, references: [], body: "Hi", bodySource: .text, attachments: []
        )
        XCTAssertEqual(reply(to: undated).markdown, "Looks good.\n\nJane Doe wrote:\n> Hi")
    }

    func testNoQuoteLeavesOutTheOriginal() {
        XCTAssertEqual(reply(to: original(), quote: false).markdown, "Looks good.")
    }

    func testAnOriginalWithoutABodyIsNotQuoted() {
        XCTAssertEqual(reply(to: original(body: "")).markdown, "Looks good.")
    }

    func testTheReplyLosesItsTrailingWhiteSpaceAndCRLFLineEnds() {
        let draft = reply(to: original(), body: "Line one\r\nLine two\n\n  \n", quote: false)
        XCTAssertEqual(draft.markdown, "Line one\nLine two")
    }

    func testTheHTMLPartIsTheMarkdownWithTheQuote() {
        let draft = reply(to: original(), body: "Looks *good*.")
        XCTAssertEqual(
            draft.html,
            "<p>Looks <em>good</em>.</p>\n<p>On 2026-10-24 13:42 CDT, Jane Doe wrote:</p>\n"
                + "<blockquote>\n<p>Can you look at the plan?</p>\n</blockquote>\n"
        )
    }
}
