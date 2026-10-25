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
