import XCTest
@testable import IrisKit

final class MarkdownHTMLTests: XCTestCase {
    private func html(_ markdown: String) -> String {
        MarkdownHTML.html(fromMarkdown: markdown)
    }

    func testMarkdownBecomesHTML() {
        XCTAssertEqual(
            html("Thanks, *Jane*.\n\n- **one**\n- two"),
            "<p>Thanks, <em>Jane</em>.</p>\n<ul>\n<li><p><strong>one</strong></p>\n</li>\n<li><p>two</p>\n</li>\n</ul>\n"
        )
    }

    func testAQuoteBecomesABlockquote() {
        XCTAssertEqual(
            html("On Monday, Jane wrote:\n> Hello\n>\n> Bye"),
            "<p>On Monday, Jane wrote:</p>\n<blockquote>\n<p>Hello</p>\n<p>Bye</p>\n</blockquote>\n"
        )
    }

    /// HTMLFormatter writes a soft break as a newline, which HTML shows as a space.
    func testEveryLineOfAMultiLineReplyKeepsItsLine() {
        XCTAssertEqual(
            html("Thanks,\nAdam\n\nSee you\n*Monday*"),
            "<p>Thanks,<br />\nAdam</p>\n<p>See you<br />\n<em>Monday</em></p>\n"
        )
        XCTAssertEqual(
            html("> one\n> two"),
            "<blockquote>\n<p>one<br />\ntwo</p>\n</blockquote>\n",
            "a quoted paragraph too"
        )
    }

    /// The image points at a MIME part of the original, which the draft does not have.
    func testACidImageIsLeftOut() {
        XCTAssertEqual(html("Best,\nJane\n\n![Image](cid:logo@01D9)"), "<p>Best,<br />\nJane</p>\n")
        XCTAssertEqual(html("Logo: ![Logo](CID:logo) here"), "<p>Logo:  here</p>\n", "in any case")
        XCTAssertEqual(
            html("![chart](https://example.com/chart.png)"),
            "<p><img src=\"https://example.com/chart.png\" /></p>\n",
            "other images stay"
        )
    }

    func testPreservedInlineIDsAllowOnlyMatchingCidImagesAndKeepEscaping() {
        let markdown = "![Logo](CID:logo%40example.com \"A & B\")\n\n"
            + "![Missing](cid:other@example.com)\n\n<script>bad()</script>"
        let rendered = MarkdownHTML.html(fromMarkdown: markdown, inlineContentIDs: ["logo@example.com"])
        XCTAssertTrue(rendered.contains("src=\"CID:logo%40example.com\""), rendered)
        XCTAssertTrue(rendered.contains("title=\"A &amp; B\""), rendered)
        XCTAssertFalse(rendered.contains("cid:other@example.com"), rendered)
        XCTAssertTrue(rendered.contains("&lt;script&gt;bad()&lt;/script&gt;"), rendered)
        XCTAssertFalse(html(markdown).contains("<img"), "new replies still discard all CID images")
    }

    /// Signatures link their logo and social icons; SwiftText keeps that as `[![Image](cid:...)](url)`.
    func testALinkLeftEmptyByACidImageIsLeftOut() {
        XCTAssertEqual(
            html("Jane\n\n[![Image](cid:logo)](https://acme.com) [![Image](cid:in)](https://linkedin.com/in/jane)"),
            "<p>Jane</p>\n",
            "the links go, then the paragraph with only the space between them"
        )
        XCTAssertEqual(
            html("[Acme ![Image](cid:logo)](https://acme.com)"),
            "<p><a href=\"https://acme.com\">Acme </a></p>\n",
            "a link that keeps its text stays"
        )
    }

    /// Outlook writes a bold signature block as <b><span><a><img src="cid:...">. The drop
    /// spreads outward: image, emphasis, link, paragraph.
    func testABoldOrItalicCidImageLeavesNothing() {
        XCTAssertEqual(html("**[![Image](cid:logo)](https://acme.com)**"), "")
        XCTAssertEqual(html("Jane\n\n**[![Image](cid:logo)](https://acme.com)**"), "<p>Jane</p>\n")
        XCTAssertEqual(html("[*![Image](cid:logo)*](https://acme.com)"), "")
        XCTAssertEqual(html("~~![Image](cid:logo)~~"), "", "strikethrough too")
    }

    /// A Gmail signature with a logo above the name.
    func testALineBreakLeftAtTheStartOfAParagraphIsLeftOut() {
        XCTAssertEqual(html("![Image](cid:logo)  \nJane Doe  \nDirector"), "<p>Jane Doe<br />\nDirector</p>\n")
        XCTAssertEqual(html("Jane Doe  \n![Image](cid:logo)"), "<p>Jane Doe</p>\n", "and at the end")
    }

    func testFormattingThatKeepsItsTextStays() {
        XCTAssertEqual(html("~~old~~ new"), "<p><del>old</del> new</p>\n")
        XCTAssertEqual(html("**Acme ![Image](cid:logo)**"), "<p><strong>Acme </strong></p>\n")
    }

    func testALinkedRemoteLogoStays() {
        XCTAssertEqual(
            html("[![logo](https://acme.com/logo.png)](https://acme.com)"),
            "<p><a href=\"https://acme.com\"><img src=\"https://acme.com/logo.png\" /></a></p>\n"
        )
    }

    func testAParagraphLeftWithOnlyALineBreakIsLeftOut() {
        XCTAssertEqual(html("Jane\n\n![Image](cid:logo)\n![Image](cid:icon)"), "<p>Jane</p>\n")
        XCTAssertEqual(html("![Image](cid:logo)  \n![Image](cid:icon)"), "", "a hard break too")
    }

    // MARK: - No setext headings

    /// Gmail quotes a plain-text message with <br> per line, and SwiftText keeps the
    /// `-- ` signature line right under the last line. As a setext heading it would
    /// merge the lines into one <h2> and drop the `--`.
    func testASignatureLineUnderAQuotedLineStaysText() {
        XCTAssertEqual(
            html("> > First line  \n> > Second line  \n> > --  \n> > Bob"),
            "<blockquote>\n<blockquote>\n<p>First line<br />\nSecond line<br />\n--<br />\nBob</p>\n</blockquote>\n</blockquote>\n"
        )
    }

    func testASignatureLineInTheReplyStaysText() {
        XCTAssertEqual(html("Thanks,\nAdam\n-- \nAdam Wulf"), "<p>Thanks,<br />\nAdam<br />\n--<br />\nAdam Wulf</p>\n")
    }

    func testAnEqualsUnderlineStaysTextAndTheNextParagraphStaysApart() {
        XCTAssertEqual(html("Title\n=====\n\nText"), "<p>Title<br />\n=====</p>\n<p>Text</p>\n")
        XCTAssertEqual(
            html("- a\n  --\n  b"),
            "<ul>\n<li><p>a<br />\n--<br />\nb</p>\n</li>\n</ul>\n",
            "in a list item too"
        )
    }

    func testAnATXHeadingStaysAHeading() {
        XCTAssertEqual(html("# Title\nText"), "<h1>Title</h1>\n<p>Text</p>\n")
    }

    func testAnUnderlineInACodeBlockIsUntouched() {
        XCTAssertEqual(html("```\nlog line\n=====\n```"), "<pre><code>log line\n=====\n</code></pre>\n")
    }

    /// A signature with a footer rule: a setext heading right after another one's underline joins it.
    func testASetextHeadingRightAfterAnotherJoinsIt() {
        XCTAssertEqual(
            html("Bob\n-- \nBob Smith\n-----\nAcme Inc."),
            "<p>Bob<br />\n--<br />\nBob Smith<br />\n-----<br />\nAcme Inc.</p>\n"
        )
    }

    func testABlockOnTheNextLineThatIsNotAParagraphStaysApart() {
        XCTAssertEqual(
            html("Title\n=====\n- item"),
            "<p>Title<br />\n=====</p>\n<ul>\n<li><p>item</p>\n</li>\n</ul>\n"
        )
    }

    func testAThematicBreakWithBlankLinesAroundItStays() {
        XCTAssertEqual(html("Text\n\n---\n\nMore"), "<p>Text</p>\n<hr />\n<p>More</p>\n")
    }

    func testTextIsEscaped() {
        XCTAssertEqual(html("x < y & \"z\" > w"), "<p>x &lt; y &amp; &quot;z&quot; &gt; w</p>\n")
    }

    func testPunctuationStaysAsTyped() {
        XCTAssertEqual(html("'Yes' -- \"no\" --- maybe..."), "<p>'Yes' -- &quot;no&quot; --- maybe...</p>\n")
    }

    func testCodeIsEscaped() {
        XCTAssertEqual(html("Use `Array<Int>`."), "<p>Use <code>Array&lt;Int&gt;</code>.</p>\n")
        XCTAssertEqual(
            html("```swift\nif a < b && c {}\n```"),
            "<pre><code class=\"language-swift\">if a &lt; b &amp;&amp; c {}\n</code></pre>\n"
        )
    }

    func testLinkTargetsAreEscaped() {
        XCTAssertEqual(
            html("[the plan](https://example.com/?a=1&b=2)"),
            "<p><a href=\"https://example.com/?a=1&amp;b=2\">the plan</a></p>\n"
        )
        XCTAssertEqual(
            html("<jane@example.com>"),
            "<p><a href=\"mailto:jane@example.com\">jane@example.com</a></p>\n"
        )
    }

    func testImageSourcesAndTitlesAreEscaped() {
        XCTAssertEqual(
            html("![a](<x\"onerror=\"y>)"),
            "<p><img src=\"x&quot;onerror=&quot;y\" /></p>\n"
        )
        XCTAssertEqual(
            html("![a](https://example.com/a.png \"say \\\"hi\\\" <b>\")"),
            "<p><img src=\"https://example.com/a.png\" title=\"say &quot;hi&quot; &lt;b&gt;\" /></p>\n"
        )
    }

    /// HTMLFormatter writes a heading's plain text, not its children.
    func testHeadingsAreEscaped() {
        XCTAssertEqual(html("# a < b & \"c\" <b>d</b>"), "<h1>a &lt; b &amp; &quot;c&quot; &lt;b&gt;d&lt;/b&gt;</h1>\n")
    }

    func testInlineAttributesAreEscaped() {
        // HTMLFormatter only puts a backslash before a quote, which does not end
        // an HTML attribute; the escaped quotes cannot end it.
        XCTAssertEqual(
            html("^[hi](x: \"1\\\" onclick=\\\"y\")"),
            "<p><span data-attributes=\"x: &quot;1\\&quot; onclick=\\&quot;y&quot;\">hi</span></p>\n"
        )
    }

    func testPlainTextIsEscapedWithALineBreakAtEachLineEnd() {
        XCTAssertEqual(
            MarkdownHTML.html(fromPlainText: "Hi <Jane> & co,\n\nThe plan\n-- \nBob"),
            "Hi &lt;Jane&gt; &amp; co,<br />\n<br />\nThe plan<br />\n-- <br />\nBob\n"
        )
        // HTML drops leading spaces and collapses runs, so they become &nbsp;, and a tab
        // becomes spaces. One space between words stays a space, so lines still wrap.
        XCTAssertEqual(
            MarkdownHTML.html(fromPlainText: "if ok {\n    run()\n}\na  b   c\n\tname:\tJane"),
            "if ok {<br />\n&nbsp;&nbsp;&nbsp;&nbsp;run()<br />\n}<br />\na &nbsp;b &nbsp;&nbsp;c<br />\n"
                + "&nbsp;&nbsp;&nbsp;&nbsp;name: &nbsp;&nbsp;&nbsp;Jane\n"
        )
    }

    /// The quoted original is untrusted: iris never emits HTML that it did not make.
    func testAQuotedHTMLTagComesOutAsText() {
        XCTAssertEqual(
            html("> <img src=x>"),
            "<blockquote>\n<p>&lt;img src=x&gt;</p>\n</blockquote>\n"
        )
    }

    func testInlineHTMLComesOutAsText() {
        XCTAssertEqual(
            html("Hi <b onclick=\"x()\">there</b>"),
            "<p>Hi &lt;b onclick=&quot;x()&quot;&gt;there&lt;/b&gt;</p>\n"
        )
    }

    func testAnHTMLBlockComesOutAsTextWithItsLines() {
        XCTAssertEqual(
            html("<script>\nalert(1)\n</script>\n\nAfter."),
            "<p>&lt;script&gt;<br />\nalert(1)<br />\n&lt;/script&gt;</p>\n<p>After.</p>\n"
        )
    }
}
