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
