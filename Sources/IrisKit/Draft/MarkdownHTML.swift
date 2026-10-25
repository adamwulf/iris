import Foundation
import Markdown

/// Renders the Markdown of a draft as HTML for its text/html part, with
/// swift-markdown's `HTMLFormatter`.
enum MarkdownHTML {
    static func html(fromMarkdown markdown: String) -> String {
        // Without smart punctuation, so the HTML says what the text part says:
        // the parser would turn "quotes" into curly ones and -- into a dash.
        let parsed = Document(parsing: markdown, options: .disableSmartOpts)
        var escaper = HTMLEscaper()
        let document = escaper.visit(parsed) ?? Document()
        return HTMLFormatter.format(document)
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
private struct HTMLEscaper: MarkupRewriter {
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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
