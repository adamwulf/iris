import Foundation
import Markdown

/// The HTML of a draft's text/html part: Markdown rendered with
/// swift-markdown's `HTMLFormatter`, and plain text escaped.
enum MarkdownHTML {
    static func html(fromMarkdown markdown: String) -> String {
        // Without smart punctuation, so the HTML says what the text part says:
        // the parser would turn "quotes" into curly ones and -- into a dash.
        let parsed = Document(parsing: markdown, options: .disableSmartOpts)
        var escaper = HTMLEscaper()
        let document = escaper.visit(parsed) ?? Document()
        return HTMLFormatter.format(document)
    }

    /// The spaces that a tab in a plain-text body becomes.
    static let tabWidth = 4

    /// `text` escaped, with `<br />` at each line end and its spaces kept. It
    /// is not read as Markdown, so a plain-text body shows as it was written:
    /// `-- ` under a line would otherwise make that line a heading.
    static func html(fromPlainText text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { keepingSpaces(escaped(String($0))) }
            .joined(separator: "<br />\n") + "\n"
    }

    /// `line` with a tab as `tabWidth` spaces, and `&nbsp;` for a space at the
    /// start or after another space. HTML drops leading spaces and collapses
    /// runs, so quoted code, logs, and aligned columns would lose their
    /// layout; a single space between words stays a space, so lines still wrap.
    static func keepingSpaces(_ line: String) -> String {
        var result = ""
        var afterSpace = true
        for character in line.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth)) {
            if character == " " {
                result += afterSpace ? "&nbsp;" : " "
                afterSpace = true
            } else {
                result.append(character)
                afterSpace = false
            }
        }
        return result
    }

    /// `text` with `&`, `<`, `>`, and `"` escaped, for HTML text and attribute values.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// `HTMLFormatter` writes text, code, and link targets as they are, so `<` in
/// a code span would start a tag. This rewrites them escaped first, as
/// CommonMark's own HTML renderer does.
///
/// It also turns raw HTML (an HTML block or inline HTML) into text, against
/// CommonMark: the quoted original is untrusted text, and a plain-text body
/// with `<img src=...>` or `<script>` would become live HTML in the draft and
/// in what the recipient gets. So iris never emits HTML that it did not make.
///
/// It also makes every soft break a line break: `HTMLFormatter` writes a soft
/// break as a bare newline, which HTML shows as a space, so "Thanks,\nAdam"
/// would read "Thanks, Adam". And it drops `cid:` images: they point at a
/// MIME part of the original (a signature logo, often), which the draft does
/// not have. The links, bold, italic, and struck text, and paragraphs that
/// they leave blank (only white space and line breaks) go too, and so do the
/// line breaks they leave at the start or end of a paragraph.
private struct HTMLEscaper: MarkupRewriter {
    static func escaped(_ text: String) -> String {
        MarkdownHTML.escaped(text)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> Markup? {
        LineBreak()
    }

    /// Whether `markup` is a line break or white-space text.
    static func isBreakOrSpace(_ markup: Markup) -> Bool {
        markup is LineBreak || markup is SoftBreak || (markup as? Text)?.string.allSatisfy(\.isWhitespace) == true
    }

    /// Whether `markup` shows nothing: every child is a line break or
    /// white-space text, or it has no children. Dropping `cid:` images leaves
    /// such nodes: two on lines next to each other leave a line break, and two
    /// linked icons leave the space between the links.
    static func isBlank(_ markup: Markup) -> Bool {
        markup.children.allSatisfy(isBreakOrSpace)
    }

    /// `markup`, or nil when it is blank. The children are rewritten first, so
    /// a drop spreads outward: image, emphasis, link, paragraph.
    static func unlessBlank(_ markup: Markup?) -> Markup? {
        guard let markup, !isBlank(markup) else {
            return nil
        }
        return markup
    }

    /// The paragraph without line breaks and white-space text at its start
    /// and end, or nil when that leaves it blank. A logo on the first line of
    /// a signature, once dropped, would leave a break before the name.
    mutating func visitParagraph(_ paragraph: Paragraph) -> Markup? {
        guard let rewritten = defaultVisit(paragraph) else {
            return nil
        }
        return Self.unlessBlank(rewritten.withUncheckedChildren(Self.trimmed(Array(rewritten.children))))
    }

    /// `inlines` without line breaks and white-space text at the start and the end.
    static func trimmed(_ inlines: [Markup]) -> [Markup] {
        var inlines = inlines
        while let first = inlines.first, isBreakOrSpace(first) {
            inlines.removeFirst()
        }
        while let last = inlines.last, isBreakOrSpace(last) {
            inlines.removeLast()
        }
        return inlines
    }

    /// Outlook writes a bold signature block as <b><span><a><img src="cid:...">, which
    /// SwiftText keeps as `**[![Image](cid:...)](https://...)**`.
    mutating func visitStrong(_ strong: Strong) -> Markup? {
        Self.unlessBlank(defaultVisit(strong))
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> Markup? {
        Self.unlessBlank(defaultVisit(emphasis))
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> Markup? {
        Self.unlessBlank(defaultVisit(strikethrough))
    }

    mutating func visitText(_ text: Text) -> Markup? {
        Text(Self.escaped(text.string))
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        InlineCode(Self.escaped(inlineCode.code))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        CodeBlock(language: codeBlock.language.map(Self.escaped), Self.escaped(codeBlock.code))
    }

    /// Nil for a link left blank: signatures link their logo and social icons,
    /// and SwiftText keeps that as `[![Image](cid:...)](https://...)`.
    mutating func visitLink(_ link: Link) -> Markup? {
        var link = link
        link.destination = link.destination.map(Self.escaped)
        return Self.unlessBlank(defaultVisit(link))
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        if image.source?.lowercased().hasPrefix("cid:") == true {
            return nil
        }
        var image = image
        image.source = image.source.map(Self.escaped)
        image.title = image.title.map(Self.escaped)
        return defaultVisit(image)
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> Markup? {
        var attributes = attributes
        attributes.attributes = Self.escaped(attributes.attributes)
        return defaultVisit(attributes)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Markup? {
        Text(Self.escaped(inlineHTML.rawHTML))
    }

    /// A paragraph with the block's text, its lines kept apart with line breaks.
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> Markup? {
        var raw = html.rawHTML
        while raw.last?.isNewline == true {
            raw.removeLast()
        }
        var inlines: [InlineMarkup] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if !inlines.isEmpty {
                inlines.append(LineBreak())
            }
            inlines.append(Text(Self.escaped(String(line))))
        }
        return Paragraph(inlines)
    }
}
