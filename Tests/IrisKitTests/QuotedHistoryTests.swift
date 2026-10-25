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
        XCTAssertTrue(QuotedHistory.isForwardMarker("============ Forwarded message ============"))
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
        // iPhone quotes its attribution with the message (seen on Zoho, 2026-10-25).
        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.
        Sent from my iPhone

        > On Oct 24, 2026, at 9:41\u{202F}PM, Jane Doe <jane@example.com> wrote:
        >\u{20}
        > \u{FEFF}Lunch on Tuesday?
        >\u{20}
        >> On Oct 24, 2026, at 9:00\u{202F}PM, Adam Wulf <adam@example.com> wrote:
        >>\u{20}
        >> Lunch?
        """), .trimmed("Sounds good.\nSent from my iPhone"))

        XCTAssertEqual(QuotedHistory.trim("""
        Sounds good.

        > On Oct 24, 2026, at 9:41 AM, Jane Doe <jane@example.com> wrote:
        > Lunch on Tuesday?

        Yes, Tuesday.
        """), .noMarker, "an answer under the quote keeps it")

        XCTAssertEqual(
            QuotedHistory.trim("Answer.\n\n> Some quote\n> On Mon, Oct 19, 2026, Bob wrote:\n> more"), .noMarker,
            "a quoted attribution counts only as the first line of a quote"
        )
        XCTAssertEqual(QuotedHistory.trim("""
        > On Oct 24, 2026, at 9:41 AM, Jane Doe <jane@example.com> wrote:
        > Lunch on Tuesday?
        Yes.
        > Same place?
        """), .noMarker, "an answer between quoted lines keeps the quote")

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

    // MARK: - Shapes seen in real mail (2026-10-25)

    func testAQuoteTheSenderWroteWithGmailsQuoteButtonIsKept() async throws {
        // Gmail's Quote button makes a blockquote.gmail_quote outside the
        // div.gmail_quote of the reply's history.
        let result = try await trimmed("""
        <div dir="ltr">Those dates work for us.<div><br></div><div>I still need an answer to my question from Monday:</div><blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex">Can the emails include the list?</blockquote><div><div dir="ltr" class="gmail_signature">Bob</div></div></div><br><div class="gmail_quote" style=""><div dir="ltr" class="gmail_attr">On Mon, Oct 12, 2026 at 10:22 AM Jane Doe &lt;jane@example.com&gt; wrote:<br></div><blockquote class="gmail_quote">Let me know who sends them.</blockquote></div>
        """)
        XCTAssertEqual(result.text, """
        Those dates work for us.

        I still need an answer to my question from Monday:

        > Can the emails include the list?
        """)
        XCTAssertTrue(result.trimmed)

        let alone = try await trimmed(#"<div>See below:</div><blockquote class="gmail_quote">The list question.</blockquote>"#)
        XCTAssertFalse(alone.trimmed)
        XCTAssertTrue(alone.text.hasSuffix("> The list question."))
    }

    func testSuperhumansHiddenTrackingImageDoesNotHideTheQuote() async throws {
        let result = try await trimmed("""
        <html><body>Thanks for the quick fix.<br/><br/>Bob<div class="gmail_signature"><div>Sent via Superhuman</div></div><div class="gmail_quote sh-color-black sh-color">On Fri, Oct 16, 2026 at 8:53 PM, Adam Wulf <span>&lt;<a href="mailto:adam@example.com">adam@example.com</a>&gt;</span> wrote:<br/><blockquote class="gmail_quote sh-color-black sh-color"><div>I just published the fix.</div></blockquote></div><div style="display: none; border: 0px; width: 0px; height: 0px; overflow: hidden; visibility: hidden;"><img src="https://example.com/pixel.gif" alt=" " width="1" height="0"/></div></body></html>
        """)
        // Its attribution is bare text in div.gmail_quote, so the signature above goes too.
        XCTAssertEqual(result.text, "Thanks for the quick fix.\n\nBob")
        XCTAssertTrue(result.trimmed)
    }

    func testAnAttributionWithoutAClassInGmailsContainerGoesInAnyLanguage() async throws {
        // Gmail's older markup: the attribution is bare text in div.gmail_quote,
        // or a plain div.
        for attribution in [
            #"Am 24. Oktober 2026 um 09:41 schrieb Jane Doe <span dir="ltr">&lt;<a href="mailto:jane@example.com">jane@example.com</a>&gt;</span>:<br>"#,
            #"<div dir="ltr">Am Fr., 24. Okt. 2026 um 09:41 Uhr schrieb Jane Doe &lt;jane@example.com&gt;:<br></div>"#,
        ] {
            let result = try await trimmed("""
            <div dir="ltr">Klingt gut.</div><div class="gmail_extra"><br><div class="gmail_quote">\(attribution)<blockquote class="gmail_quote">Mittagessen am Dienstag?</blockquote></div></div>
            """)
            XCTAssertEqual(result.text, "Klingt gut.", attribution)
            XCTAssertTrue(result.trimmed, attribution)
        }
    }

    func testAnAnswerUnderABareAttributionIsKept() async throws {
        // The attribution has no class, so only the lines left in the
        // container tell it from an answer written there.
        for answer in ["Yes, Tuesday works.<br><br>", #"<img src="cid:photo"><br>"#] {
            let result = try await trimmed("""
            <div dir="ltr">See below.</div><div class="gmail_quote">On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <span>&lt;jane@example.com&gt;</span> wrote:<br><br>\(answer)<blockquote class="gmail_quote">Lunch on Tuesday?</blockquote></div>
            """)
            XCTAssertTrue(result.text.contains("wrote:"), "\(answer): \(result.text)")
            XCTAssertTrue(result.trimmed, answer)
        }
        let kept = try await trimmed("""
        <div dir="ltr">See below.</div><div class="gmail_quote">On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <span>&lt;jane@example.com&gt;</span> wrote:<br><br>Yes, Tuesday works.<br><br><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote></div>
        """)
        XCTAssertTrue(kept.text.hasSuffix("Yes, Tuesday works."), kept.text)

        // A one-line answer above a marked attribution, inside the container.
        for container in [
            #"<div class="gmail_quote gmail_quote_container"><div dir="ltr">Tuesday works for me.</div><div class="gmail_attr">On Fri, Jane wrote:<br></div><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote></div>"#,
            #"<div class="zmail_extra"><div>Tuesday works for me.<br></div><div id="Zm-_Id_-Sgn1">Von: Jane Doe<br>Datum: Fr., 23 Okt. 2026<br>Betreff: Mittagessen<br></div><div><br></div><blockquote id="blockquote_zmail"><div>Mittagessen am Dienstag?</div></blockquote></div>"#,
        ] {
            let marked = try await trimmed("<div>Hi Jane,<br></div>" + container)
            XCTAssertEqual(marked.text, "Hi Jane,\n\nTuesday works for me.", container)
            XCTAssertTrue(marked.trimmed, container)
        }

        // Bare-text answers between quoted lines: the earlier quote stays too.
        let inline = try await trimmed("""
        <div>See inline.</div><div class="gmail_quote">On Fri, Jane wrote:<br><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote>Yes, Tuesday works.<br><blockquote class="gmail_quote">See you!</blockquote></div>
        """)
        XCTAssertTrue(inline.trimmed)
        XCTAssertTrue(inline.text.contains("> Lunch on Tuesday?"), inline.text)
        XCTAssertTrue(inline.text.hasSuffix("Yes, Tuesday works."), inline.text)
    }

    func testAHiddenElementAloneIsNotHistory() async throws {
        let result = try await trimmed(#"<p>Hi there.</p><div style="display:none"><img src="https://example.com/pixel.gif"></div>"#)
        XCTAssertEqual(result.text, "Hi there.")
        XCTAssertFalse(result.trimmed)
    }

    func testZohoWebReplyInAnyLanguage() async throws {
        // Zoho's header has the original's From, Date, and Subject, here in German.
        let result = try await trimmed("""
        <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"><html><head><meta content="text/html;charset=UTF-8" http-equiv="Content-Type"></head><body ><div style="font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10pt;"><div>Gerne!<br></div><div><br></div><div>Adam<br></div><div><br></div><div><br></div><div class="zmail_extra_hr" style="border-top: 1px solid rgb(204, 204, 204); height: 0px; margin-top: 10px; margin-bottom: 10px; line-height: 0px; display: none;"><br></div><div class="zmail_extra" data-zbluepencil-ignore="true" style="clear: both;"><div><br></div><div id="Zm-_Id_-Sgn1">Von: Jane Doe &lt;jane@example.com&gt;<br>Datum: Fr., 23 Okt. 2026 10:28:18 -0500<br>Betreff: Mittagessen<br></div><div><br></div><blockquote style="margin: 0px;" id="blockquote_zmail"><div>Mittagessen am Dienstag?</div></blockquote></div><div><br></div></div><br></body></html>
        """)
        XCTAssertEqual(result.text, "Gerne!\n\nAdam")
        XCTAssertTrue(result.trimmed)

        // Zoho's ids count only inside its container.
        let alone = try await trimmed(#"<div>See below:</div><blockquote id="blockquote_zmail"><div>My note.</div></blockquote>"#)
        XCTAssertFalse(alone.trimmed)
        XCTAssertTrue(alone.text.hasSuffix("My note."), alone.text)
    }

    func testAnswersInAnEnglishZohoReplyAreKept() async throws {
        // In English, Zoho's header looks like Outlook's From/Date/Subject
        // block, which the text pass would cut with everything under it.
        let header = #"<div><br></div><div id="Zm-_Id_-Sgn1">From: Jane Doe &lt;jane@example.com&gt;<br>Date: Fri, 23 Oct 2026 10:28:18 -0500<br>Subject: Lunch<br></div><div><br></div>"#
        let plain = try await trimmed(#"<div>Sounds good.</div><div class="zmail_extra">"# + header + #"<blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div>"#)
        XCTAssertEqual(plain.text, "Sounds good.")
        XCTAssertTrue(plain.trimmed)

        let under = try await trimmed(#"<div>Hi Jane,</div><div class="zmail_extra">"# + header + #"<div>Tuesday works for me.</div><blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div>"#)
        XCTAssertTrue(under.text.hasSuffix("Tuesday works for me."), under.text)
        XCTAssertTrue(under.text.contains("Subject: Lunch"), under.text)

        let inline = try await trimmed(#"<div>See inline.</div><div class="zmail_extra">"# + header + #"<blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote><div>Yes, Tuesday works.</div><blockquote id="blockquote_zmail"><div>See you!</div></blockquote></div>"#)
        XCTAssertTrue(inline.text.contains("> Lunch on Tuesday?"), inline.text)
        XCTAssertTrue(inline.text.hasSuffix("Yes, Tuesday works."), inline.text)

        // A signature above the container does not cut the answers either.
        let signed = try await trimmed(#"<div>Hi Jane,</div><div>-- <br>Adam</div><div class="zmail_extra">"# + header + #"<div>Tuesday works for me.</div><blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div>"#)
        XCTAssertTrue(signed.text.hasSuffix("Tuesday works for me."), signed.text)
    }

    func testAnOutlookStyleReplyToAZohoReplyIsCutAtItsHeader() async throws {
        // Classic Outlook and Samsung Email put an unmarked header over the
        // message they answer; here that message is an English Zoho reply.
        let zoho = #"<div>Sounds good, Tuesday it is.<br></div><div class="zmail_extra"><div><br></div><div id="Zm-_Id_-Sgn1">From: Bob &lt;bob@example.com&gt;<br>Date: Fri, 23 Oct 2026 10:28:18 -0500<br>Subject: Lunch<br></div><div><br></div><blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div>"#
        for header in [
            #"<div style="border:none;border-top:solid #E1E1E1 1.0pt"><p class="MsoNormal"><b>From:</b> Jane Doe &lt;jane@example.com&gt;<br><b>Sent:</b> Friday, October 23, 2026 11:00 AM<br><b>To:</b> Bob<br><b>Subject:</b> RE: Lunch</p></div>"#,
            #"<div>-------- Original message --------</div><div>From: Jane Doe &lt;jane@example.com&gt;</div><div>Date: 10/23/26 11:00 AM (GMT-06:00)</div><div>To: Bob</div><div>Subject: Re: Lunch</div><div><br></div>"#,
        ] {
            let result = try await trimmed("<div><p>Great, see you then.</p>" + header + "<div>" + zoho + "</div></div>")
            XCTAssertEqual(result.text, "Great, see you then.", header)
            XCTAssertTrue(result.trimmed, header)

            // A disclaimer that the Outlook side's server adds stops the HTML
            // walk, so Zoho's header is left; Outlook's header still cuts.
            let disclaimer = try await trimmed(
                "<div><p>Great, see you then.</p>" + header + "<div>" + zoho + "</div></div><div>CONFIDENTIALITY NOTICE: This email is for its recipients only.</div>"
            )
            XCTAssertEqual(disclaimer.text, "Great, see you then.", header)

            // The Zoho reply has an answer under its header, which keeps it.
            let answered = zoho.replacingOccurrences(of: #"<div><br></div><blockquote"#, with: #"<div>Noon works.</div><blockquote"#)
            let under = try await trimmed("<div><p>Great, see you then.</p>" + header + "<div>" + answered + "</div></div>")
            XCTAssertEqual(under.text, "Great, see you then.", header)

            // With nothing above Zoho's header, its lines come right under
            // Outlook's: they are still two header blocks.
            let bare = answered.replacingOccurrences(of: "<div>Sounds good, Tuesday it is.<br></div>", with: "<div><br></div>")
            let merged = try await trimmed("<div><p>Great, see you then.</p>" + header + "<div>" + bare + "</div></div>")
            XCTAssertEqual(merged.text, "Great, see you then.", header)
        }

        // New Outlook wraps the history in its container; with a disclaimer
        // under it, that container is not at the end either.
        let newOutlook = try await trimmed(
            #"<div>Great, see you then.</div><div id="mail-editor-reference-message-container"><div><b>From:</b> Jane Doe &lt;jane@example.com&gt;<br><b>Sent:</b> Friday, October 23, 2026 11:00 AM<br><b>Subject:</b> RE: Lunch</div>"#
                + zoho + "</div><div>This message is confidential.</div>"
        )
        XCTAssertEqual(newOutlook.text, "Great, see you then.")
    }

    func testAZohoForwardIsKept() async throws {
        let html = """
        <div><div>FYI<br></div><div><br></div><div class="zmail_extra_hr" style="border-top: 1px solid rgb(204, 204, 204); height: 0px; margin-top: 10px; margin-bottom: 10px; line-height: 0px;"><br></div><div class="zmail_extra" data-zbluepencil-ignore="true"><div><br></div><div id="1">============ Forwarded message ============<br>From: Jane Doe &lt;jane@example.com&gt;<br>Date: Fri, 16 Oct 2026 16:16:00 -0500<br>Subject: Lunch<br>============ Forwarded message ============<br></div><div><br></div><blockquote style="margin: 0px;" id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div></div>
        """
        let result = try await trimmed(html)
        XCTAssertFalse(result.trimmed)
        let full = try await whole(html)
        XCTAssertEqual(result.text, full)
        XCTAssertTrue(result.text.contains("Lunch on Tuesday?"))
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

        // Without "Re:", the HTML pass keeps a quote that starts a forward:
        // it could be the forward itself.
        let notReply = try await trimmed(gmail)
        XCTAssertFalse(notReply.trimmed)
        XCTAssertTrue(notReply.text.contains("Lunch on Tuesday?"))

        // But iPhone's quoted attribution above it (`> On ... wrote:`) marks
        // a reply's quote, so the text pass cuts it.
        let quotedAttribution = try await trimmed(iPhone)
        XCTAssertEqual(quotedAttribution.text, "Thanks!")
        XCTAssertTrue(quotedAttribution.trimmed)
    }

    func testTheDOMPassLeavesAGmailForwardAlone() async throws {
        // The Markdown pass would keep these forwards whole too (by parsing
        // again); this checks that the DOM pass does not touch them.
        let signed = try await MessageDecoder.htmlDocument(fromHTML: """
        <div>FYI</div><div class="gmail_quote"><div class="gmail_attr">---------- Forwarded message ---------<br>From: Jane</div><div>Lunch on Tuesday?</div><div class="gmail_signature">Jane</div></div>
        """)
        XCTAssertEqual(QuotedHistory.removeHistory(fromHTMLParts: [signed]), QuotedHistory.Removal(keptForward: true))

        let outlook = try await MessageDecoder.htmlDocument(fromHTML: """
        <div>FYI</div><div class="gmail_quote"><div class="gmail_attr">---------- Forwarded message ---------<br>From: Jane</div><div>Sounds good.</div><hr><div id="divRplyFwdMsg"><b>From:</b> Bob<br><b>Sent:</b> Thursday<br><b>Subject:</b> Lunch</div><div>Who is in?</div></div>
        """)
        XCTAssertEqual(
            QuotedHistory.removeHistory(fromHTMLParts: [outlook]), QuotedHistory.Removal(keptForward: true),
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

    func testGmailAnswersUnderTheSignatureAreKept() async throws {
        // Gmail puts the signature above the quote, so inline answers are under it.
        let result = try await trimmed("""
        <div dir="ltr">See inline.<br clear="all"><div><br></div><span class="gmail_signature_prefix">-- </span><br><div dir="ltr" class="gmail_signature">Adam</div></div><br><div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">On Fri, Oct 24, 2026 at 9:41 AM Jane Doe &lt;jane@example.com&gt; wrote:<br></div><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote><div>Yes, Tuesday works.</div><blockquote class="gmail_quote">Same place?</blockquote><div>No, the new one.</div></div>
        """)
        XCTAssertTrue(result.text.contains("> Same place?"), result.text)
        XCTAssertTrue(result.text.hasSuffix("No, the new one."), result.text)
        XCTAssertFalse(result.trimmed)

        XCTAssertEqual(QuotedHistory.trim("""
        See inline.

        --\u{20}
        Adam

        On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:

        > Lunch on Tuesday?

        Yes, Tuesday works.
        """), .noMarker, "plain text too")
    }

    func testASignatureAboveTheHistoryStillCutsWhenNoAnswerFollows() async throws {
        let footer = "-- \nYou received this message because you are subscribed to the Google Groups \"Lunch\" group."
        // Plain text: a list footer under the quote, a quote in another
        // language, and a quote with no attribution.
        for history in [
            "On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:\n\n> Lunch on Tuesday?\n\n" + footer,
            "Am Fr., 24. Okt. 2026 um 09:41 Uhr schrieb Jane Doe <jane@example.com>:\n\n> Mittagessen am Dienstag?",
            "> Lunch on Tuesday?",
        ] {
            XCTAssertEqual(QuotedHistory.trim("Sounds good.\n\n-- \nAdam\n\n" + history), .trimmed("Sounds good."), history)
        }

        // HTML: a Gmail reply with a signature, to a Google Group.
        let gmail = try await trimmed("""
        <div dir="ltr">Sounds good.<br clear="all"><div><br></div><span class="gmail_signature_prefix">-- </span><br><div dir="ltr" class="gmail_signature">Adam</div></div><br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Fri, Jane wrote:<br></div><blockquote class="gmail_quote">Lunch on Tuesday?</blockquote></div><p></p>-- <br />You received this message because you are subscribed to the Google Groups "Lunch" group.<br />
        """)
        XCTAssertEqual(gmail.text, "Sounds good.")
        XCTAssertTrue(gmail.trimmed)

        // A Zoho reply to a Google Group: the walk stops at the footer, so
        // Zoho's header is left, and only the footer is cut. (A header that is
        // left may have the sender's answers under it.)
        let zoho = try await trimmed("""
        <div>Sounds good.</div><div class="zmail_extra"><div><br></div><div id="Zm-_Id_-Sgn1">From: Jane Doe &lt;jane@example.com&gt;<br>Date: Fri, 23 Oct 2026 10:28:18 -0500<br>Subject: Lunch<br></div><div><br></div><blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div><p></p>-- <br />You received this message because you are subscribed to the Google Groups "Lunch" group.<br />
        """)
        XCTAssertTrue(zoho.text.hasSuffix("> Lunch on Tuesday?"), zoho.text)
        XCTAssertTrue(zoho.trimmed)

        // A Gmail reply without "Re:" that quotes a forward: the walk keeps
        // the forward, but its English attribution makes it history, which
        // the signature rule does not look into, so the signature still cuts.
        let forward = try await trimmed("""
        <div dir="ltr">Thanks<br><span class="gmail_signature_prefix">-- </span><br><div class="gmail_signature">Adam</div></div><div class="gmail_quote"><div class="gmail_attr">On Fri, Oct 24, 2026 at 9:41 AM Jane Doe &lt;jane@example.com&gt; wrote:<br></div><blockquote class="gmail_quote">---------- Forwarded message ---------<br>From: Bob<br><br>Lunch on Tuesday?</blockquote></div>
        """)
        XCTAssertEqual(forward.text, "Thanks")

        // A quote with no mark in Zoho's container: the text pass finds it,
        // and it is no answer, so the signature above it cuts too.
        let unmarked = try await trimmed("""
        <div>Sounds good.</div><div>-- <br>Adam</div><div class="zmail_extra"><div>---- On Fri, 24 Oct 2026 09:41:00 -0500 Jane Doe &lt;jane@example.com&gt; wrote ----<br></div><blockquote style="margin: 0px;"><div>Lunch on Tuesday?</div></blockquote></div>
        """)
        XCTAssertEqual(unmarked.text, "Sounds good.")
    }

    func testAnswersInAZohoReplyAreKeptWhateverFollowsTheContainer() async throws {
        let header = #"<div><br></div><div id="Zm-_Id_-Sgn1">From: Jane Doe &lt;jane@example.com&gt;<br>Date: Fri, 23 Oct 2026 10:28:18 -0500<br>Subject: Lunch<br></div><div><br></div>"#
        let groups = #"<p></p>-- <br />You received this message because you are subscribed to the Google Groups "Lunch" group.<br />"#
        let disclaimer = "<div>This message is confidential.</div>"
        for footer in [groups, disclaimer] {
            let inline = try await trimmed(#"<div>See inline.</div><div class="zmail_extra">"# + header + #"<blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote><div>Yes, Tuesday works.</div><blockquote id="blockquote_zmail"><div>See you!</div></blockquote></div>"# + footer)
            XCTAssertTrue(inline.text.contains("Yes, Tuesday works."), "\(footer): \(inline.text)")

            let under = try await trimmed(#"<div>Hi Jane,</div><div class="zmail_extra">"# + header + #"<div>Tuesday works for me.</div><blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div>"# + footer)
            XCTAssertTrue(under.text.contains("Tuesday works for me."), "\(footer): \(under.text)")
        }

        // A bottom-post: the reply is under Zoho's container, with a signature above it.
        let bottom = try await trimmed(#"<div>Hi Jane,</div><div>-- <br>Adam</div><div class="zmail_extra">"# + header + #"<blockquote id="blockquote_zmail"><div>Lunch on Tuesday?</div></blockquote></div><div>Sounds good, see you Tuesday.</div>"#)
        XCTAssertTrue(bottom.text.hasSuffix("Sounds good, see you Tuesday."), bottom.text)
    }

    func testASignatureAboveAKeptForwardKeepsIt() async throws {
        // An Apple Mail forward with an edited subject: its "Begin forwarded
        // message:" line is inside the quote, which the HTML pass keeps.
        let forward = try await trimmed("""
        <html><body>Have a look at this.<div>-- <br>Adam</div><div><br><blockquote type="cite"><div>Begin forwarded message:</div><br class="Apple-interchange-newline"><div><b>From: </b>Jane Doe &lt;jane@example.com&gt;</div><div><b>Subject: </b>Lunch</div><br><div>Lunch on Tuesday?</div></blockquote></div></body></html>
        """)
        XCTAssertTrue(forward.text.contains("Lunch on Tuesday?"), forward.text)
        XCTAssertFalse(forward.trimmed)

        XCTAssertEqual(QuotedHistory.trim("""
        Have a look at this.
        --\u{20}
        Adam

        > Begin forwarded message:
        >
        > From: Jane Doe <jane@example.com>
        >
        > Lunch on Tuesday?
        """), .noMarker, "plain text too")
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
