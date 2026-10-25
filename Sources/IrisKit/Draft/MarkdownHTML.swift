import Foundation
import Markdown

/// The HTML of a draft's text/html part: Markdown rendered with
/// swift-markdown's `HTMLFormatter`, and plain text escaped.
enum MarkdownHTML {
    static func html(fromMarkdown markdown: String) -> String {
        // Without smart punctuation, so the HTML says what the text part says:
        // the parser would turn "quotes" into curly ones and -- into a dash.
        let parsed = Document(parsing: markdown, options: .disableSmartOpts)
        var escaper = HTMLEscaper(source: markdown)
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
///
/// And iris never makes a setext heading: a line of only `-` or `=` under a
/// text line stays text. In email that line is the `-- ` signature separator
/// (RFC 3676), and as a heading it would merge the lines above it into one
/// `<h2>` and drop the `--`. The rule works on the parsed tree, so a `=====`
/// line in a code block is never touched.
private struct HTMLEscaper: MarkupRewriter {
    /// The Markdown's lines, to read the underline of a setext heading.
    private let sourceLines: [Substring]

    init(source: String) {
        sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)
    }

    static func escaped(_ text: String) -> String {
        MarkdownHTML.escaped(text)
    }

    mutating func visitDocument(_ document: Document) -> Markup? {
        document.withUncheckedChildren(rewrittenBlocks(of: document))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> Markup? {
        blockQuote.withUncheckedChildren(rewrittenBlocks(of: blockQuote))
    }

    mutating func visitListItem(_ listItem: ListItem) -> Markup? {
        listItem.withUncheckedChildren(rewrittenBlocks(of: listItem))
    }

    /// The blocks of `container`, rewritten, with each setext heading turned
    /// back into the text it was: its lines, a line break, and the underline.
    /// A paragraph or setext heading that starts on the next line joins it
    /// after a line break, as it did in the text: after a setext heading,
    /// CommonMark starts a new paragraph even without a blank line.
    private mutating func rewrittenBlocks(of container: Markup) -> [Markup] {
        var blocks: [Markup] = []
        // The inlines of the paragraph that a setext heading became, and its
        // last line, while a block on the next line can still join it.
        var open: (inlines: [Markup], lastLine: Int)?
        func close() {
            if let open, let paragraph = Self.paragraph(open.inlines) {
                blocks.append(paragraph)
            }
            open = nil
        }
        for child in container.children {
            let startsOnNextLine = open.map { child.range?.lowerBound.line == $0.lastLine + 1 } ?? false
            if let heading = child as? Heading, let underline = setextUnderline(of: heading) {
                let inlines = heading.children.compactMap { visit($0) }
                    + [LineBreak(), Text(Self.escaped(underline.text))]
                if startsOnNextLine, let current = open {
                    open = (current.inlines + [LineBreak()] + inlines, underline.line)
                } else {
                    close()
                    open = (inlines, underline.line)
                }
                continue
            }
            if startsOnNextLine, let current = open, child is Paragraph {
                let paragraph = visit(child).map { Array($0.children) } ?? []
                open = (current.inlines + [LineBreak()] + paragraph, current.lastLine)
                close()
                continue
            }
            close()
            if let rewritten = visit(child) {
                blocks.append(rewritten)
            }
        }
        close()
        return blocks
    }

    /// The underline of a setext heading (`---` or `===`) and its line
    /// number. Nil for an ATX heading (`# Title`), whose range is one line.
    ///
    /// swift-markdown ends a setext heading's range at the end of its
    /// container, not at the underline, so this looks for the underline: the
    /// first line after the first that holds only `-` or only `=` after the
    /// markers of its containers (`> > `, or a list item's indent). A line of
    /// the heading's text cannot look like that: it would be the underline.
    private func setextUnderline(of heading: Heading) -> (text: String, line: Int)? {
        guard let range = heading.range, range.upperBound.line > range.lowerBound.line else {
            return nil
        }
        for number in (range.lowerBound.line + 1)...range.upperBound.line where sourceLines.indices.contains(number - 1) {
            let line = sourceLines[number - 1].trimmingCharacters(in: .whitespaces)
            let underline = String(line.reversed().prefix(while: { $0 == "-" || $0 == "=" }))
            let markers = line.dropLast(underline.count)
            if Set(underline).count == 1, markers.allSatisfy({ $0 == ">" || $0.isWhitespace }) {
                return (underline, number)
            }
        }
        return nil
    }

    /// A paragraph of `inlines` (already rewritten), trimmed, or nil when blank.
    private static func paragraph(_ inlines: [Markup]) -> Markup? {
        let trimmed = trimmed(inlines).compactMap { $0 as? InlineMarkup }
        return trimmed.isEmpty ? nil : unlessBlank(Paragraph(trimmed))
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
