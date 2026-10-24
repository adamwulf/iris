import Foundation
import XCTest
@testable import IrisKit

final class MessageDecoderTests: XCTestCase {
    /// Raw message bytes from text with `\n` line ends, sent as CRLF the way a server sends them.
    private func eml(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    private let alternative = """
    From: Jane Doe <jane@example.com>
    To: adam@example.com
    Subject: Hello
    Content-Type: multipart/alternative; boundary="alt"

    --alt
    Content-Type: text/plain; charset=utf-8

    Hello *world*
    --alt
    Content-Type: text/html; charset=utf-8

    <p>Hello <b>world</b></p>
    --alt--

    """

    func testPlainTextIsNotEscaped() async throws {
        let document = try await MessageDecoder.decode(eml("""
        From: jane@example.com
        To: adam@example.com
        Subject: Plain
        Content-Type: text/plain; charset=us-ascii

        Use *stars*, _underscores_ and <tags>.\u{20}\u{20}
        # Not a heading

        """))

        XCTAssertEqual(document.body, "Use *stars*, _underscores_ and <tags>.  \n# Not a heading")
        XCTAssertEqual(document.bodySource, .text)
    }

    func testHTMLOnlyIsConvertedToMarkdown() async throws {
        let document = try await MessageDecoder.decode(eml("""
        From: news@example.com
        Subject: News
        Content-Type: text/html; charset=utf-8

        <html><head><style>p{color:red}</style></head><body><h1>Weekly News</h1>
        <p>Hello &amp; welcome. Read <a href="https://example.com/a">the article</a>.</p></body></html>

        """))

        XCTAssertEqual(document.body, "# Weekly News\n\nHello & welcome. Read [the article](https://example.com/a).")
        XCTAssertEqual(document.bodySource, .html)
    }

    func testAlternativeAutoPicksHTML() async throws {
        let document = try await MessageDecoder.decode(eml(alternative))
        XCTAssertEqual(document.body, "Hello **world**")
        XCTAssertEqual(document.bodySource, .html)
    }

    func testAlternativeTextPicksText() async throws {
        let document = try await MessageDecoder.decode(eml(alternative), body: .text)
        XCTAssertEqual(document.body, "Hello *world*")
        XCTAssertEqual(document.bodySource, .text)
    }

    func testAlternativeHTMLPicksHTML() async throws {
        let document = try await MessageDecoder.decode(eml(alternative), body: .html)
        XCTAssertEqual(document.body, "Hello **world**")
        XCTAssertEqual(document.bodySource, .html)
    }

    func testMissingChosenPartFallsBackToTheOther() async throws {
        let textOnly = try await MessageDecoder.decode(eml("""
        Subject: Text only

        Just text.
        """), body: .html)
        XCTAssertEqual(textOnly.body, "Just text.")
        XCTAssertEqual(textOnly.bodySource, .text)

        let htmlOnly = try await MessageDecoder.decode(eml("""
        Subject: HTML only
        Content-Type: text/html

        <p>Just <i>HTML</i>.</p>
        """), body: .text)
        XCTAssertEqual(htmlOnly.body, "Just *HTML*.")
        XCTAssertEqual(htmlOnly.bodySource, .html)
    }

    func testQuotedPrintableISO88591AndAStaleMetaCharset() async throws {
        let message = eml("""
        Subject: Dessert
        Content-Type: multipart/alternative; boundary="b"

        --b
        Content-Type: text/plain; charset=ISO-8859-1
        Content-Transfer-Encoding: quoted-printable

        Caf=E9 cr=E8me br=FBl=E9e, with a soft line =
        break.
        --b
        Content-Type: text/html; charset="iso-8859-1"
        Content-Transfer-Encoding: quoted-printable

        <html><head><meta http-equiv=3D"Content-Type" content=3D"text/html; charset=
        =3Diso-8859-1"></head><body><p>Caf=E9 cr=E8me</p></body></html>
        --b--
        """)

        let text = try await MessageDecoder.decode(message, body: .text)
        XCTAssertEqual(text.body, "Café crème brûlée, with a soft line break.")

        let html = try await MessageDecoder.decode(message, body: .html)
        XCTAssertEqual(html.body, "Café crème")
    }

    func testBase64UTF8() async throws {
        let html = "<p>Hello <b>wörld</b> ✓, this paragraph is long enough to wrap the base64 lines.</p>"
        let encoded = Data(html.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        let document = try await MessageDecoder.decode(eml("""
        Subject: Base64
        Content-Type: text/html; charset=UTF-8
        Content-Transfer-Encoding: base64

        \(encoded)
        """))

        XCTAssertTrue(encoded.contains("\n"))
        XCTAssertEqual(document.body, "Hello **wörld** ✓, this paragraph is long enough to wrap the base64 lines.")
    }

    func testRFC2047SubjectAndDisplayNames() async throws {
        let document = try await MessageDecoder.decode(eml("""
        From: =?UTF-8?B?QW5kcsOp?= <andre@example.com>
        To: =?ISO-8859-1?Q?Ren=E9_Dupont?= <rene@example.com>, plain@example.com
        Cc: "Doe, Jane" <jane@example.com>
        Reply-To: Team: a@example.com, B <b@example.com>;
        Subject: =?UTF-8?Q?Caf=C3=A9?= and =?UTF-8?B?w4ljaGFudGlsbG9u?=

        Body
        """))

        XCTAssertEqual(document.subject, "Café and Échantillon")
        XCTAssertEqual(document.from, [MessageAddress(name: "André", email: "andre@example.com")])
        XCTAssertEqual(document.to, [
            MessageAddress(name: "René Dupont", email: "rene@example.com"),
            MessageAddress(name: nil, email: "plain@example.com"),
        ])
        XCTAssertEqual(document.cc, [MessageAddress(name: "Doe, Jane", email: "jane@example.com")])
        XCTAssertEqual(document.replyTo, [
            MessageAddress(name: nil, email: "a@example.com"),
            MessageAddress(name: "B", email: "b@example.com"),
        ])
    }

    func testAddressTextThatIsNotAnAddressIsKept() async throws {
        let document = try await MessageDecoder.decode(eml("""
        From: MAILER-DAEMON
        To: undisclosed-recipients:;

        Bounce
        """))

        XCTAssertEqual(document.from, [MessageAddress(name: nil, email: "MAILER-DAEMON")])
        XCTAssertEqual(document.to, [])
    }

    func testFullDocumentWithAnRFC2231Attachment() async throws {
        let document = try await MessageDecoder.decode(eml("""
        Message-ID: <reply-2@example.com>
        In-Reply-To: <first@example.com>
        References: <root@example.com>
         <first@example.com>
        From: Jane Doe <jane@example.com>
        To: Adam <adam@example.com>
        Date: Sat, 24 Oct 2026 13:42:00 -0500
        Subject: CV
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="mixed"

        --mixed
        Content-Type: text/plain; charset=utf-8

        Attached.
        --mixed
        Content-Type: application/pdf; name="resume.pdf"
        Content-Disposition: attachment; filename*=UTF-8''r%C3%A9sum%C3%A9.pdf
        Content-Transfer-Encoding: base64

        SGVsbG8gV29ybGQ=
        --mixed--
        """))

        XCTAssertEqual(document, MessageDocument(
            messageID: "<reply-2@example.com>",
            subject: "CV",
            from: [MessageAddress(name: "Jane Doe", email: "jane@example.com")],
            to: [MessageAddress(name: "Adam", email: "adam@example.com")],
            cc: [],
            replyTo: [],
            date: ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z"),
            inReplyTo: "<first@example.com>",
            references: ["<root@example.com>", "<first@example.com>"],
            body: "Attached.",
            bodySource: .text,
            attachments: [MessageAttachment(filename: "résumé.pdf", contentType: "application/pdf", size: 11)]
        ))
    }

    func testMissingSubjectDateAndFrom() async throws {
        let document = try await MessageDecoder.decode(eml("""
        To: adam@example.com

        No headers to speak of.
        """))

        XCTAssertNil(document.subject)
        XCTAssertNil(document.date)
        XCTAssertNil(document.messageID)
        XCTAssertEqual(document.from, [])
        XCTAssertEqual(document.body, "No headers to speak of.")
    }

    func testDateWithATrailingCommentIsRead() async throws {
        let document = try await MessageDecoder.decode(eml("""
        Date: Sat, 24 Oct 2026 13:42:00 -0500 (CDT)

        Body
        """))

        XCTAssertEqual(document.date, ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z"))
    }

    func testMessageWithOnlyAnAttachmentHasNoBody() async throws {
        let document = try await MessageDecoder.decode(eml("""
        Subject: Scan
        Content-Type: multipart/mixed; boundary="m"

        --m
        Content-Type: image/png
        Content-Disposition: attachment; filename="scan.png"
        Content-Transfer-Encoding: base64

        iVBORw0KGgo=
        --m--
        """))

        XCTAssertEqual(document.body, "")
        XCTAssertNil(document.bodySource)
        XCTAssertEqual(document.attachments, [MessageAttachment(filename: "scan.png", contentType: "image/png", size: 8)])
    }

    func testGmailQuoteBecomesMarkdownQuote() async throws {
        let document = try await MessageDecoder.decode(eml("""
        From: Adam <adam@example.com>
        Subject: Re: Meeting
        Content-Type: multipart/alternative; boundary="000000000000abc"

        --000000000000abc
        Content-Type: text/plain; charset="UTF-8"

        Sounds good, see you then.

        -- Adam

        On Mon, Oct 20, 2026 at 9:14 AM Jane Doe <jane@example.com> wrote:
        > Can we meet Tuesday?
        --000000000000abc
        Content-Type: text/html; charset="UTF-8"

        <div dir="ltr">Sounds good, see you then.<br><br>-- Adam</div><br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">On Mon, Oct 20, 2026 at 9:14 AM Jane Doe &lt;jane@example.com&gt; wrote:<br></div><blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex"><div>Can we meet <b>Tuesday</b> at <a href="https://example.com/cal">the usual place</a>?</div><ul><li>Agenda item one</li><li>Agenda item two</li></ul></blockquote></div>
        --000000000000abc--
        """))

        XCTAssertEqual(document.bodySource, .html)
        XCTAssertEqual(document.body, """
        Sounds good, see you then.

        -- Adam

        On Mon, Oct 20, 2026 at 9:14 AM Jane Doe <jane@example.com> wrote:

        > Can we meet **Tuesday** at [the usual place](https://example.com/cal)?
        >
        > - Agenda item one
        > - Agenda item two
        """)
    }

    func testFormatFlowedIsUnwrapped() async throws {
        let document = try await MessageDecoder.decode(eml("""
        Subject: Flowed
        Content-Type: text/plain; charset=utf-8; format=flowed

        This paragraph was wrapped by the\u{20}
        sender at a soft break.

        > A quoted line that is also\u{20}
        > wrapped.
        """))

        XCTAssertEqual(document.body, """
        This paragraph was wrapped by the sender at a soft break.

        > A quoted line that is also wrapped.
        """)
    }

    func testFormatFlowedWithDelSpInAMultipart() async throws {
        let document = try await MessageDecoder.decode(eml("""
        Subject: Flowed delsp
        Content-Type: multipart/alternative; boundary="b"

        --b
        Content-Type: text/plain; charset="UTF-8"; format="Flowed"; delsp="yes"

        Supercalifragi\u{20}
        listic and\u{20}\u{20}
        more.
        --b--
        """))

        XCTAssertEqual(document.body, "Supercalifragilistic and more.")
    }

    func testTextWithoutFormatFlowedKeepsItsLineBreaks() async throws {
        let document = try await MessageDecoder.decode(eml("""
        Subject: Fixed
        Content-Type: text/plain; charset=utf-8

        Line one ends in a space\u{20}
        line two.
        """))

        XCTAssertEqual(document.body, "Line one ends in a space\nline two.")
    }

    func testEmptyDataIsNotAMessage() async {
        do {
            _ = try await MessageDecoder.decode(Data())
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? IrisError, .messageNotParsed(reason: "No headers found in the message"))
        }
    }

    func testContentTypeParameters() {
        XCTAssertEqual(
            MessageDecoder.contentTypeParameters("text/plain; charset=\"a;b\"; FORMAT=flowed; format=fixed; junk"),
            ["charset": "a;b", "format": "flowed"]
        )
    }

    func testDeclaringUTF8OnlyChangesMetaTags() {
        XCTAssertEqual(
            MessageDecoder.declaringUTF8("<META CHARSET='windows-1252'><meta content=\"text/html; charset=koi8-r\"><p>charset=x</p>"),
            "<META CHARSET='utf-8'><meta content=\"text/html; charset=utf-8\"><p>charset=x</p>"
        )
    }
}
