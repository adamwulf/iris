import Foundation
import XCTest
@testable import IrisKit

final class QuotedHistoryTests: XCTestCase {
    // MARK: - Forwards

    func testAForwardSubjectStartsWithFwdOrFwAfterTags() {
        XCTAssertTrue(QuotedHistory.isForward(subject: "Fwd: Lunch"))
        XCTAssertTrue(QuotedHistory.isForward(subject: "FW: Lunch"))
        XCTAssertTrue(QuotedHistory.isForward(subject: "fw : Lunch"))
        XCTAssertTrue(QuotedHistory.isForward(subject: "[list] [EXTERNAL] Fwd: Lunch"))
        XCTAssertFalse(QuotedHistory.isForward(subject: "Re: Fwd: Lunch"), "a reply to a forward")
        XCTAssertFalse(QuotedHistory.isForward(subject: "Lunch"))
        XCTAssertFalse(QuotedHistory.isForward(subject: "Fwding the plan"))
        XCTAssertFalse(QuotedHistory.isForward(subject: nil))
    }

    func testAReplySubjectStartsWithReAfterTags() {
        XCTAssertTrue(QuotedHistory.isReply(subject: "Re: Lunch"))
        XCTAssertTrue(QuotedHistory.isReply(subject: "[list] RE: Fwd: Lunch"))
        XCTAssertFalse(QuotedHistory.isReply(subject: "Fwd: Re: Lunch"))
        XCTAssertFalse(QuotedHistory.isReply(subject: "Recipe for lunch"))
        XCTAssertFalse(QuotedHistory.isReply(subject: nil))
    }

    func testForwardMarkers() {
        XCTAssertTrue(QuotedHistory.isForwardMarker("---------- Forwarded message ---------"))
        XCTAssertTrue(QuotedHistory.isForwardMarker("-------- Forwarded Message --------"))
        XCTAssertTrue(QuotedHistory.isForwardMarker("Begin forwarded message:"))
        XCTAssertFalse(QuotedHistory.isForwardMarker("I forwarded the message to Jane."))
    }

    // MARK: - Plain text

    func testGmailPlainTextReply() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:

        > Lunch on Tuesday?
        >
        > Jane
        """), .trimmed("Sounds good."))
    }

    func testAnAttributionWrappedOntoTwoLines() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe-Smithfield <jane.doe-smithfield@example.com>
        wrote:

        > Lunch on Tuesday?
        """), .trimmed("Sounds good."))
    }

    func testAppleMailPlainTextReplyKeepsSentFromMyIPhone() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        Sent from my iPhone

        > On Oct 24, 2026, at 9:41 AM, Jane Doe <jane@example.com> wrote:
        >
        > Lunch on Tuesday?
        """), .noMarker, "the attribution is quoted too, so there is no marker")

        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        Sent from my iPhone

        On Oct 24, 2026, at 9:41 AM, Jane Doe <jane@example.com> wrote:

        > Lunch on Tuesday?
        """), .trimmed("Sounds good.\n\nSent from my iPhone"))
    }

    func testZohoAttribution() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        ---- On Fri, 24 Oct 2026 09:41:00 -0500 Jane Doe <jane@example.com> wrote ----

        > Lunch on Tuesday?
        """), .trimmed("Sounds good."))
    }

    func testASignatureIsCut() {
        XCTAssertEqual(QuotedHistory.trim("Sounds good.\n\n-- \nAdam Wulf\n555-0100"), .trimmed("Sounds good."))
    }

    func testOnlyMarkdownFromHTMLTakesADoubleDashWithoutTheSpace() {
        // SwiftText writes "-- " as "--", or as "--" with a hard break.
        for text in ["Sounds good.\n\n--\nAdam", "Sounds good.\n\n--  \nAdam"] {
            XCTAssertEqual(QuotedHistory.trim(text, fromHTML: true), .trimmed("Sounds good."), text)
            XCTAssertEqual(QuotedHistory.trim(text), .noMarker, "plain text needs RFC 3676's \"-- \": \(text)")
        }
    }

    func testASignatureAboveTheQuoteIsCutWithIt() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        --\u{20}
        Adam

        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:
        > Lunch on Tuesday?
        """), .trimmed("Sounds good."))
    }

    func testAQuoteWithASignatureUnderItIsCut() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:
        > Lunch on Tuesday?

        --\u{20}
        Adam
        """), .trimmed("Sounds good."))
    }

    func testOutlookPlainTextReply() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        ________________________________
        From: Jane Doe <jane@example.com>
        Sent: Friday, October 24, 2026 9:41 AM
        To: Adam Wulf <adam@example.com>
        Subject: Lunch

        Lunch on Tuesday?
        """), .trimmed("Sounds good."))
    }

    func testOutlookOriginalMessageWithCc() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        -----Original Message-----
        From: Jane Doe <jane@example.com>
        Sent: Friday, October 24, 2026 9:41 AM
        To: Adam Wulf <adam@example.com>
        Cc: Team <team@example.com>
        Subject: RE: Lunch

        Lunch on Tuesday?
        """), .trimmed("Sounds good."))
    }

    func testOutlookHeaderWithBoldLabelsInMarkdown() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        **From:** Jane Doe <jane@example.com>\u{20}\u{20}
        **Sent:** Friday, October 24, 2026 9:41 AM\u{20}\u{20}
        **To:** Adam Wulf <adam@example.com>\u{20}\u{20}
        **Subject:** Lunch

        Lunch on Tuesday?
        """), .trimmed("Sounds good."))
    }

    func testOutlookForMacHeaderHasDateInsteadOfSent() {
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        From: Jane Doe <jane@example.com>
        Date: Friday, October 24, 2026 at 9:41 AM
        To: Adam Wulf <adam@example.com>
        Subject: Lunch

        Lunch on Tuesday?
        """), .trimmed("Sounds good."))
    }

    func testEveryHeaderSeparatorIsCutWithTheHeader() {
        for separator in ["***", "* * *", "-----", "__________"] {
            XCTAssertEqual(QuotedHistory.trim("""
            Sounds good.

            \(separator)

            From: Jane Doe <jane@example.com>
            Sent: Friday, October 24, 2026 9:41 AM
            Subject: Lunch

            Lunch on Tuesday?
            """), .trimmed("Sounds good."), separator)
        }
    }

    func testAFromLineAloneIsNoHeader() {
        XCTAssertEqual(QuotedHistory.trim("""
        From: the desk of Jane
        To: everyone

        Lunch is on Tuesday.
        """), .noMarker)
    }

    func testAnInterleavedReplyIsKept() {
        XCTAssertEqual(QuotedHistory.trim("""
        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:
        > Lunch on Tuesday?

        Yes.

        > Same place?

        No, the new one.
        """), .noMarker)
    }

    func testABottomPostedReplyKeepsTheQuoteAndLosesTheSignature() {
        XCTAssertEqual(QuotedHistory.trim("""
        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:
        > Lunch on Tuesday?

        Yes.
        --\u{20}
        Adam
        """), .trimmed("""
        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:
        > Lunch on Tuesday?

        Yes.
        """))
    }

    func testAQuoteWithoutAnAttributionIsKept() {
        XCTAssertEqual(QuotedHistory.trim("Sounds good.\n\n> Lunch on Tuesday?"), .noMarker)
    }

    func testAQuotedSignatureSeparatorIsNotASignature() {
        XCTAssertEqual(QuotedHistory.trim("Sounds good.\n\n> -- \n> Jane"), .noMarker)
    }

    func testAnAttributionWithNothingUnderItIsKeptUnlessAQuoteWasRemoved() {
        let text = "Sounds good.\n\nOn Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:"
        XCTAssertEqual(QuotedHistory.trim(text), .noMarker)
        XCTAssertEqual(QuotedHistory.trim(text, afterRemovedQuote: true), .trimmed("Sounds good."))
    }

    func testAForwardIsNotCut() {
        XCTAssertEqual(QuotedHistory.trim("""
        FYI

        ---------- Forwarded message ---------
        From: Jane Doe <jane@example.com>
        Date: Fri, Oct 24, 2026 at 9:41 AM
        Subject: Lunch
        To: <adam@example.com>

        Lunch on Tuesday?
        --\u{20}
        Jane
        """), .forward)
        XCTAssertEqual(QuotedHistory.trim("FYI\n\nBegin forwarded message:\n\nFrom: Jane\n\nLunch on Tuesday?"), .forward)
    }

    func testAForwardWithTheSignatureAboveItIsNotCut() {
        XCTAssertEqual(QuotedHistory.trim("""
        FYI
        --\u{20}
        Adam

        ---------- Forwarded message ---------
        From: Jane Doe <jane@example.com>
        Date: Fri, Oct 24, 2026 at 9:41 AM
        Subject: Lunch

        Lunch on Tuesday?
        """), .forward)
    }

    func testAnOutlookReplyInAThreadThatStartedWithAForwardIsCut() {
        // Outlook does not quote the history, so the forward marker is in it, unquoted.
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        ________________________________
        From: Jane Doe <jane@example.com>
        Sent: Friday, October 24, 2026 9:41 AM
        To: Adam Wulf <adam@example.com>
        Subject: Fwd: Lunch

        FYI

        ---------- Forwarded message ---------
        From: Bob <bob@example.com>
        Date: Thu, Oct 23, 2026 at 5:00 PM
        Subject: Lunch

        Who is in?
        """), .trimmed("Sounds good."))
    }

    func testAReplyThatQuotesAForwardIsCut() {
        XCTAssertEqual(QuotedHistory.trim("""
        Thanks!

        On Fri, Oct 24, 2026 at 10:00 AM Adam Wulf <adam@example.com> wrote:
        > FYI
        >
        > ---------- Forwarded message ---------
        > From: Jane Doe <jane@example.com>
        """), .trimmed("Thanks!"))
    }

    func testABodyThatIsAllHistoryIsKept() {
        XCTAssertEqual(
            QuotedHistory.trim("On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:\n> Lunch?"), .allHistory
        )
        XCTAssertEqual(QuotedHistory.trim("-- \nAdam"), .allHistory)
    }

    func testAHardBreakBeforeTheCutIsRemoved() {
        XCTAssertEqual(
            QuotedHistory.trim("Sounds good.  \n-- \nAdam"),
            .trimmed("Sounds good."),
            "a hard break at the end does nothing"
        )
    }

    // MARK: - HTML

    /// The HTML parts converted with trimming, as the decoder does it.
    private func trimmed(_ parts: String...) async throws -> (text: String, trimmed: Bool) {
        try await MessageDecoder.markdown(
            fromHTMLParts: parts, hasTextPart: false, trimming: true, parseHTML: MessageDecoder.htmlDocument(fromHTML:)
        )
    }

    /// The HTML parts of a reply (a `Re:` subject) converted with trimming.
    private func trimmedReply(_ parts: String...) async throws -> (text: String, trimmed: Bool) {
        try await MessageDecoder.markdown(
            fromHTMLParts: parts, hasTextPart: false, trimming: true, inReply: true,
            parseHTML: MessageDecoder.htmlDocument(fromHTML:)
        )
    }

    /// The HTML parts converted without trimming.
    private func whole(_ parts: String...) async throws -> String {
        try await MessageDecoder.markdown(
            fromHTMLParts: parts, hasTextPart: false, trimming: false, parseHTML: MessageDecoder.htmlDocument(fromHTML:)
        ).text
    }

    func testGmailReplyLosesItsQuoteAndSignature() async throws {
        let result = try await trimmed("""
        <div dir="ltr">Sounds good.<br clear="all"><div><br></div><span class="gmail_signature_prefix">-- </span><br><div dir="ltr" class="gmail_signature" data-smartmail="gmail_signature"><div dir="ltr">Adam Wulf<div>555-0100</div></div></div></div><br><div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">On Fri, Oct 24, 2026 at 9:41 AM Jane Doe &lt;<a href="mailto:jane@example.com">jane@example.com</a>&gt; wrote:<br></div><blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex"><div dir="ltr">Lunch on Tuesday?</div></blockquote></div>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testGmailForwardIsKept() async throws {
        let html = """
        <div dir="ltr">FYI<br><br><div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">---------- Forwarded message ---------<br>From: <strong class="gmail_sendername" dir="auto">Jane Doe</strong> <span dir="auto">&lt;<a href="mailto:jane@example.com">jane@example.com</a>&gt;</span><br>Date: Fri, Oct 24, 2026 at 9:41 AM<br>Subject: Lunch<br>To: &lt;<a href="mailto:adam@example.com">adam@example.com</a>&gt;<br></div><br><br><div dir="ltr">Lunch on Tuesday?</div></div></div>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)
    }

    func testAForwardKeepsTheQuoteAndSignatureOfTheMessageItForwards() async throws {
        // A Gmail forward whose subject has no "Fwd:": the forwarded message
        // has its own quote and signature, which are part of the forward.
        let html = """
        <div dir="ltr">FYI<br><br><div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">---------- Forwarded message ---------<br>From: Jane Doe &lt;jane@example.com&gt;<br>Date: Fri, Oct 24, 2026 at 9:41 AM<br>Subject: Lunch<br></div><br><div dir="ltr">Lunch on Tuesday?<br><span class="gmail_signature_prefix">-- </span><br><div class="gmail_signature">Jane</div></div><br><div class="gmail_quote"><div class="gmail_attr">On Thu, Oct 23, 2026 Bob wrote:<br></div><blockquote class="gmail_quote">Who is in?</blockquote></div></div></div>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)
        XCTAssertTrue(result.text.contains("Who is in?"))
    }

    func testAReplyToAForwardWithoutANoteLosesTheQuotedForward() async throws {
        // The quote starts with the forward marker: in a reply, it is the
        // forward the reply answers. iPhone puts the attribution in its own blockquote.
        let iPhone = """
        <html><body dir="auto"><div dir="ltr">Thanks!</div><div dir="ltr"><br><blockquote type="cite">On Oct 24, 2026, at 10:00 AM, Adam Wulf &lt;adam@example.com&gt; wrote:<br><br></blockquote></div><blockquote type="cite"><div dir="ltr"><div class="gmail_quote"><div class="gmail_attr">---------- Forwarded message ---------<br>From: Jane Doe &lt;jane@example.com&gt;<br>Subject: Lunch<br></div><div>Lunch on Tuesday?</div></div></div></blockquote></body></html>
        """
        let reply = try await trimmedReply(iPhone)
        XCTAssertEqual(reply.text, "Thanks!")
        XCTAssertTrue(reply.trimmed)

        let gmail = """
        <div dir="ltr">Danke!</div><br><div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">Am Fr., 24. Okt. 2026 um 10:00 Uhr schrieb Adam Wulf &lt;adam@example.com&gt;:<br></div><blockquote class="gmail_quote"><div dir="ltr">---------- Forwarded message ---------<br>From: Jane Doe &lt;jane@example.com&gt;<br>Subject: Lunch<br><br>Lunch on Tuesday?</div></blockquote></div>
        """
        let german = try await trimmedReply(gmail)
        XCTAssertEqual(german.text, "Danke!")
        XCTAssertTrue(german.trimmed)

        // The same HTML in a message that is not a reply could be the forward itself.
        let notReply = try await trimmed(iPhone)
        XCTAssertFalse(notReply.trimmed)
        XCTAssertTrue(notReply.text.contains("Lunch on Tuesday?"))
    }

    func testTheDOMPassLeavesAGmailForwardAlone() async throws {
        // The Markdown pass would keep these forwards whole too (by parsing
        // again); this checks that the DOM pass does not touch them.
        let signed = try await MessageDecoder.htmlDocument(fromHTML: """
        <div>FYI</div><div class="gmail_quote"><div class="gmail_attr">---------- Forwarded message ---------<br>From: Jane</div><div>Lunch on Tuesday?</div><div class="gmail_signature">Jane</div></div>
        """)
        XCTAssertEqual(QuotedHistory.removeHistory(fromHTMLParts: [signed]), QuotedHistory.Removal())

        let outlook = try await MessageDecoder.htmlDocument(fromHTML: """
        <div>FYI</div><div class="gmail_quote"><div class="gmail_attr">---------- Forwarded message ---------<br>From: Jane</div><div>Sounds good.</div><hr><div id="divRplyFwdMsg"><b>From:</b> Bob<br><b>Sent:</b> Thursday<br><b>Subject:</b> Lunch</div><div>Who is in?</div></div>
        """)
        XCTAssertEqual(
            QuotedHistory.removeHistory(fromHTMLParts: [outlook]), QuotedHistory.Removal(),
            "an Outlook header inside the forward is part of it"
        )
    }

    func testAnEmptyReplyWithItsAttributionAboveTheQuoteIsShownWhole() async throws {
        // Older Apple Mail, a reply with only an attachment: the attribution
        // is all that would be left.
        let html = """
        <html><body><div><div>On Oct 24, 2026, at 9:41 AM, Jane Doe &lt;jane@example.com&gt; wrote:</div><br class="Apple-interchange-newline"><blockquote type="cite"><div>Lunch on Tuesday?</div></blockquote></div></body></html>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)
        XCTAssertTrue(result.text.contains("Lunch on Tuesday?"))
    }

    func testATypedSignatureSeparatorInHTML() async throws {
        for html in ["<div>Sounds good.</div><div>-- </div><div>Adam Wulf</div>", "<p>Sounds good.<br>-- <br>Adam Wulf</p>"] {
            let result = try await trimmed(html)
            XCTAssertEqual(result.text, "Sounds good.", html)
            XCTAssertTrue(result.trimmed, html)
        }
    }

    func testNewOutlookReferenceContainer() async throws {
        let result = try await trimmed("""
        <div>Sounds good.</div><div id="mail-editor-reference-message-container"><hr><div><b>From:</b> Jane Doe<br><b>Sent:</b> Friday<br><b>Subject:</b> Lunch</div><div>Lunch on Tuesday?</div></div>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testGmailMarksDoNotDependOnTheLanguage() async throws {
        // The text rules know only English; the classes find this quote.
        let result = try await trimmed("""
        <div dir="ltr">Klingt gut.</div><br><div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">Am Fr., 24. Okt. 2026 um 09:41 Uhr schrieb Jane Doe &lt;jane@example.com&gt;:<br></div><blockquote class="gmail_quote">Mittagessen am Dienstag?</blockquote></div>
        """)
        XCTAssertEqual(result.text, "Klingt gut.")
        XCTAssertTrue(result.trimmed)
    }

    func testGmailAnswersBetweenTheQuotedLinesAreKept() async throws {
        // Gmail splits the blockquote around each answer, inside div.gmail_quote.
        let html = """
        <div>Answers inline below.</div><div class="gmail_quote gmail_quote_container"><div class="gmail_attr">On Fri, Oct 24, 2026 at 9:41 AM Jane Doe &lt;jane@example.com&gt; wrote:<br></div><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote><div>Yes, Tuesday works.</div><blockquote class="gmail_quote">Same place?</blockquote><div>No, the new one on Main St.</div></div>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)

        // A quoted line left without an answer at the end goes.
        let unanswered = try await trimmed("""
        <div>Answers inline below.</div><div class="gmail_quote"><div class="gmail_attr">On Fri, Jane wrote:<br></div><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote><div>Yes, Tuesday works.</div><blockquote class="gmail_quote">See you!</blockquote></div>
        """)
        XCTAssertTrue(unanswered.trimmed)
        XCTAssertTrue(unanswered.text.hasSuffix("Yes, Tuesday works."), unanswered.text)
        XCTAssertTrue(unanswered.text.contains("> Lunch on Tuesday?"), unanswered.text)
    }

    func testAGoogleGroupsFooterIsCutWithTheQuoteAboveIt() async throws {
        let result = try await trimmed("""
        <div dir="ltr">Sounds good.</div><br><div class="gmail_quote"><div class="gmail_attr">On Fri, Jane wrote:<br></div><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote></div><p></p>-- <br />You received this message because you are subscribed to the Google Groups "Lunch" group.<br />
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testAnAttributionLikeLineIsKeptWhenOnlyASignatureWasRemoved() async throws {
        let result = try await trimmed("""
        <div>Notes from the call.</div><div>On Monday, Bob wrote:</div><div class="gmail_signature">Adam</div>
        """)
        XCTAssertEqual(result.text, "Notes from the call.\n\nOn Monday, Bob wrote:")
        XCTAssertTrue(result.trimmed, "the signature is gone")
    }

    func testAnOutlookHeaderInsideAnotherAppsQuoteKeepsTheTextAfterTheQuote() async throws {
        // A Thunderbird reply under the quote of an Outlook message.
        let result = try await trimmed("""
        <html><body><div class="moz-cite-prefix">On 10/24/26 9:41 AM, Jane Doe wrote:<br></div><blockquote type="cite"><div>Lunch on Tuesday?</div><hr><div id="divRplyFwdMsg"><b>From:</b> Bob<br><b>Sent:</b> Thursday<br><b>Subject:</b> Lunch</div><div>Who is in?</div></blockquote><p>Sounds good.</p></body></html>
        """)
        XCTAssertFalse(result.trimmed)
        XCTAssertTrue(result.text.hasSuffix("Sounds good."), result.text)
    }

    func testAppleMailIPhoneReply() async throws {
        let result = try await trimmed("""
        <html><head><meta http-equiv="content-type" content="text/html; charset=utf-8"></head><body dir="auto"><div dir="ltr">Sounds good.</div><div dir="ltr"><br></div><div dir="ltr">Sent from my iPhone</div><div dir="ltr"><br><blockquote type="cite">On Oct 24, 2026, at 9:41 AM, Jane Doe &lt;jane@example.com&gt; wrote:<br><br></blockquote></div><blockquote type="cite"><div dir="ltr">Lunch on Tuesday?</div></blockquote></body></html>
        """)
        XCTAssertEqual(result.text, "Sounds good.\n\nSent from my iPhone")
        XCTAssertTrue(result.trimmed)
    }

    func testAppleMailMacReply() async throws {
        let result = try await trimmed("""
        <html><head><meta http-equiv="content-type" content="text/html; charset=utf-8"></head><body style="overflow-wrap: break-word; -webkit-nbsp-mode: space; line-break: after-white-space;">Sounds good.<div><br></div><div><br><blockquote type="cite"><div>On Oct 24, 2026, at 9:41 AM, Jane Doe &lt;jane@example.com&gt; wrote:</div><br class="Apple-interchange-newline"><div><div>Lunch on Tuesday?</div></div></blockquote></div><br></body></html>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testAnAttributionAboveTheBlockquoteGoesWithIt() async throws {
        let result = try await trimmed("""
        <html><body>Sounds good.<div><br><div><div>On Oct 24, 2026, at 9:41 AM, Jane Doe &lt;jane@example.com&gt; wrote:</div><br class="Apple-interchange-newline"><blockquote type="cite"><div>Lunch on Tuesday?</div></blockquote></div><br></div></body></html>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testAppleMailForwardIsKept() async throws {
        let html = """
        <html><body>FYI<div><br><div><br><blockquote type="cite"><div>Begin forwarded message:</div><br class="Apple-interchange-newline"><div style="margin-top: 0px;"><span><b>From: </b></span><span>Jane Doe &lt;jane@example.com&gt;</span></div><div><span><b>Subject: </b></span><span><b>Lunch</b></span></div><div><span><b>Date: </b></span><span>October 24, 2026 at 9:41:00 AM CDT</span></div><div><span><b>To: </b></span><span>Adam &lt;adam@example.com&gt;</span></div><br><div><div>Lunch on Tuesday?</div><div><br><blockquote type="cite"><div>On Oct 23, 2026, at 5:00 PM, Bob wrote:</div><div>Who is in?</div></blockquote></div></div></blockquote></div><br></div></body></html>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)
        XCTAssertTrue(result.text.contains("Lunch on Tuesday?"))
        XCTAssertTrue(result.text.contains("Who is in?"), "the forwarded message's own quote is part of the forward")
    }

    func testThunderbirdReplyAboveTheQuote() async throws {
        let result = try await trimmed("""
        <html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></head><body><p>Sounds good.</p><div class="moz-signature">-- <br>Adam</div><div class="moz-cite-prefix">On 10/24/26 9:41 AM, Jane Doe wrote:<br></div><blockquote type="cite" cite="mid:abc@example.com"><p>Lunch on Tuesday?</p></blockquote></body></html>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testThunderbirdReplyBelowTheQuoteKeepsTheQuote() async throws {
        let result = try await trimmed("""
        <html><body><div class="moz-cite-prefix">On 10/24/26 9:41 AM, Jane Doe wrote:<br></div><blockquote type="cite" cite="mid:abc@example.com"><p>Lunch on Tuesday?</p></blockquote><p>Sounds good.</p><div class="moz-signature">-- <br>Adam</div></body></html>
        """)
        XCTAssertEqual(result.text, "On 10/24/26 9:41 AM, Jane Doe wrote:\n\n> Lunch on Tuesday?\n\nSounds good.")
        XCTAssertTrue(result.trimmed, "the signature is gone")
    }

    func testOutlookWebReply() async throws {
        let result = try await trimmed("""
        <html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"><style type="text/css" style="display:none;"> P {margin-top:0;margin-bottom:0;} </style></head><body dir="ltr"><div class="elementToProof" style="font-family: Aptos, sans-serif; font-size: 12pt;">Sounds good.</div><div id="appendonsend"></div><hr style="display:inline-block;width:98%" tabindex="-1"><div id="divRplyFwdMsg" dir="ltr"><font face="Calibri, sans-serif" style="font-size:11pt" color="#000000"><b>From:</b> Jane Doe &lt;jane@example.com&gt;<br><b>Sent:</b> Friday, October 24, 2026 9:41 AM<br><b>To:</b> Adam Wulf &lt;adam@example.com&gt;<br><b>Subject:</b> Lunch</font><div>&nbsp;</div></div><div><div dir="ltr">Lunch on Tuesday?</div></div></body></html>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testOutlookDesktopReply() async throws {
        let result = try await trimmed("""
        <html xmlns:o="urn:schemas-microsoft-com:office:office"><head><meta http-equiv=Content-Type content="text/html; charset=utf-8"><style>p.MsoNormal{margin:0in;}</style></head><body lang=EN-US link="#0563C1" vlink="#954F72"><div class=WordSection1><p class=MsoNormal>Sounds good.<o:p></o:p></p><p class=MsoNormal><o:p>&nbsp;</o:p></p><div><div style='border:none;border-top:solid #E1E1E1 1.0pt;padding:3.0pt 0in 0in 0in'><p class=MsoNormal><b>From:</b> Jane Doe &lt;jane@example.com&gt; <br><b>Sent:</b> Friday, October 24, 2026 9:41 AM<br><b>To:</b> Adam Wulf &lt;adam@example.com&gt;<br><b>Subject:</b> Lunch<o:p></o:p></p></div></div><p class=MsoNormal><o:p>&nbsp;</o:p></p><p class=MsoNormal>Lunch on Tuesday?<o:p></o:p></p></div></body></html>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testAnHTMLQuoteWithoutAMarkerIsFoundByItsAttribution() async throws {
        // A plain blockquote, under a Zoho-style attribution line.
        let result = try await trimmed("""
        <div><div>Sounds good.<br></div><div><br></div><div class="zmail_extra"><div>---- On Fri, 24 Oct 2026 09:41:00 -0500 <b>Jane Doe &lt;jane@example.com&gt;</b> wrote ----<br></div><div><br></div><blockquote style="margin: 0px;"><div>Lunch on Tuesday?</div></blockquote></div></div>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testAnInterleavedHTMLReplyIsKept() async throws {
        let html = """
        <html><body><div>On Oct 24, 2026, at 9:41 AM, Jane Doe &lt;jane@example.com&gt; wrote:</div><blockquote type="cite"><div>Lunch on Tuesday?</div></blockquote><div>Yes.</div><blockquote type="cite"><div>Same place?</div></blockquote><div>No, the new one.</div></body></html>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)
    }

    func testAnHTMLBodyThatIsAllQuoteIsKept() async throws {
        let html = """
        <div class="gmail_quote"><div class="gmail_attr">On Fri, Oct 24, 2026 at 9:41 AM Jane wrote:<br></div><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote></div>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)
        XCTAssertTrue(result.text.contains("Lunch on Tuesday?"))
    }

    func testAFooterAfterTheHTMLEndDoesNotHideTheQuote() async throws {
        let result = try await trimmed("""
        <html><body><p>Sounds good.</p><blockquote type="cite"><p>Lunch on Tuesday?</p></blockquote></body></html>
        <p>Sent through the list server.</p>
        """)
        XCTAssertEqual(result.text, "Sounds good.")
        XCTAssertTrue(result.trimmed)
    }

    func testAnImageAfterTheQuoteKeepsIt() async throws {
        let html = """
        <p>Sounds good.</p><blockquote type="cite"><p>Lunch on Tuesday?</p></blockquote><p><img src="cid:photo"></p>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
    }

    func testTheEndOfSeveralPartsIsTrimmedFromTheLastOne() async throws {
        // Apple Mail splits the body around an attachment.
        let emptied = try await trimmed(
            #"<div>Sounds good.</div><div class="gmail_signature">Adam</div>"#,
            #"<div class="gmail_quote"><div class="gmail_attr">On Fri, Jane wrote:</div><blockquote class="gmail_quote">Lunch?</blockquote></div>"#
        )
        XCTAssertEqual(emptied.text, "Sounds good.", "the last part is all quote, so the one before loses its signature too")
        XCTAssertTrue(emptied.trimmed)

        let kept = try await trimmed(
            #"<div>Sounds good.</div><div class="gmail_signature">Adam</div>"#,
            #"<div>One more thing.</div><div class="gmail_quote"><div class="gmail_attr">On Fri, Jane wrote:</div><blockquote class="gmail_quote">Lunch?</blockquote></div>"#
        )
        XCTAssertEqual(kept.text, "Sounds good.\n\nAdam\n\nOne more thing.", "the last part has text, so the part before is not touched")
        XCTAssertTrue(kept.trimmed)
    }

    func testAPathFindsTheFirstElementInDocumentOrder() async throws {
        let document = try await MessageDecoder.htmlDocument(fromHTML: #"<div><p id="a">1</p></div><div id="b"><p id="a">2</p></div>"#)
        let root = QuotedHistory.contentRoot(of: document)
        let path = try XCTUnwrap(QuotedHistory.path(in: root) { QuotedHistory.attribute("id", of: $0) == "a" })
        let last = try XCTUnwrap(path.last)
        XCTAssertEqual(last.parent.children[last.index].text().trimmingCharacters(in: .whitespacesAndNewlines), "1")
    }
}
