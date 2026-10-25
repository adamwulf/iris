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

    /// `text` escaped, with `<br />` at each line end. It is not read as
    /// Markdown, so a plain-text body shows as it was written: `-- ` under a
    /// line would otherwise make that line a heading.
    static func html(fromPlainText text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { escaped(String($0)) }
            .joined(separator: "<br />\n") + "\n"
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
/// not have.
private struct HTMLEscaper: MarkupRewriter {
    static func escaped(_ text: String) -> String {
        MarkdownHTML.escaped(text)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> Markup? {
        LineBreak()
    }

    /// Nil for a paragraph left empty, such as one that held only a `cid:` image.
    mutating func visitParagraph(_ paragraph: Paragraph) -> Markup? {
        let rewritten = defaultVisit(paragraph)
        return rewritten?.childCount == 0 ? nil : rewritten
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

    mutating func visitLink(_ link: Link) -> Markup? {
        var link = link
        link.destination = link.destination.map(Self.escaped)
        return defaultVisit(link)
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
