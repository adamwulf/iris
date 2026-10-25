import Foundation
import SwiftTextHTML

/// Finds the quoted history and the signature at the end of a body, so that
/// `iris show` and `iris thread` can leave them out (`--full` keeps them). A
/// reply usually quotes the whole conversation under it, and a thread shows
/// each of those messages anyway.
///
/// Only the end of a body is cut, and only at a marker that a common mail app
/// writes. A quote with new text after it (answers between quoted lines, or
/// under them) is kept, and so is a body with no marker. A forward is never
/// cut: the message it forwards is new to the reader.
enum QuotedHistory {
    // MARK: - Forwards

    /// Whether `subject` is a forward's: after any `[tags]`, it starts with
    /// `Fwd:` or `Fw:` (any case). A reply to a forward ("Re: Fwd: x") is not one.
    static func isForward(subject: String?) -> Bool {
        withoutTags(subject).prefixMatch(of: /(?:fwd|fw)\s*:/.ignoresCase()) != nil
    }

    /// Whether `subject` is a reply's: after any `[tags]`, it starts with
    /// `Re:` (any case). Gmail, Apple Mail, and Thunderbird write `Re:` in
    /// every language.
    static func isReply(subject: String?) -> Bool {
        withoutTags(subject).prefixMatch(of: /re\s*:/.ignoresCase()) != nil
    }

    /// `subject` without the `[tags]` and the whitespace at its start.
    static func withoutTags(_ subject: String?) -> String {
        var text = subject ?? ""
        if let tags = text.prefixMatch(of: /\s*(?:\[[^\]]*\]\s*)*/) {
            text.removeSubrange(tags.range)
        }
        return text
    }

    /// Whether `line` starts a forwarded message: Gmail's
    /// `---------- Forwarded message ---------`, Thunderbird's
    /// `-------- Forwarded Message --------`, Zoho's
    /// `============ Forwarded message ============`, or Apple Mail's
    /// `Begin forwarded message:`.
    static func isForwardMarker(_ line: some StringProtocol) -> Bool {
        let text = String(line).trimmingCharacters(in: .whitespaces)
        return text.wholeMatch(of: /-+ *forwarded message *-+/.ignoresCase()) != nil
            || text.wholeMatch(of: /=+ *forwarded message *=+/.ignoresCase()) != nil
            || text.wholeMatch(of: /begin forwarded message:/.ignoresCase()) != nil
    }

    // MARK: - Text

    /// What `trim(_:fromHTML:afterRemovedQuote:findingOutlookHeader:keptAnswers:)` did with a text.
    enum TextTrim: Equatable {
        /// The text has no marker, so nothing is cut.
        case noMarker
        /// The text has an unquoted forward marker (`isForwardMarker(_:)`)
        /// above its quoted history, so nothing is cut. A marker inside an
        /// Outlook reply's history (which Outlook does not quote) is an
        /// earlier message's, and does not count.
        case forward
        /// The cut would leave nothing, so nothing is cut.
        case allHistory
        /// The text without its quoted history and signature.
        case trimmed(String)
    }

    /// `text`, a cleaned body (plain text, or Markdown from HTML), without the
    /// quoted history and signature at its end.
    ///
    /// The cut starts at the first of these:
    /// - The signature separator, a line that is exactly `-- `. In Markdown
    ///   from HTML, also a line that is `--` with only spaces after it:
    ///   SwiftText drops the space, or writes a hard break after it. Not when
    ///   an answer follows it (an unquoted line under a quoted line, before
    ///   the history or the next `-- ` line), or when `keptAnswers`.
    /// - An attribution line, `On <date>, <name> wrote:` (it may wrap onto a
    ///   second line) or Zoho's `---- On <date> <name> wrote ----`, with only
    ///   quoted (`>`) and blank lines after it, at least one of them quoted,
    ///   up to a `-- ` line (a signature or a list footer under the quote)
    ///   or the end. Also the same line quoted as the
    ///   first line of a quote (`> On ... wrote:`, as iPhone and Apple Mail
    ///   write it in plain text), with the same lines after it.
    /// - Outlook's header block: a `From:` line with `Sent:` (or `Date:`) and
    ///   `Subject:` among the label lines under it (the labels may be bold),
    ///   from the separator line above it when there is one (`_____`,
    ///   `-----Original Message-----`, or a thematic break). Outlook does not
    ///   quote the message under it, so the cut runs to the end.
    ///
    /// - Parameters:
    ///   - fromHTML: Whether `text` is Markdown converted from HTML.
    ///   - afterRemovedQuote: Whether an HTML quote was removed from the end.
    ///     Then an attribution line with nothing after it starts the cut too:
    ///     it was the removed quote's (older Apple Mail puts it above the
    ///     `blockquote`).
    ///   - findingOutlookHeader: Whether Outlook's header block starts the
    ///     cut. False when Zoho's marked header is left after the HTML pass
    ///     (`hasZohoHeader(in:)`): in English its From/Date/Subject lines
    ///     look like Outlook's, and what follows it may be the sender's.
    ///   - keptAnswers: Whether the HTML pass stopped at the sender's text
    ///     inside a reply's quote container (`Removal.keptAnswers`). Then the
    ///     signature does not start the cut.
    static func trim(
        _ text: String,
        fromHTML: Bool = false,
        afterRemovedQuote: Bool = false,
        findingOutlookHeader: Bool = true,
        keptAnswers: Bool = false
    ) -> TextTrim {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // The sender's signature, and any list footer (Google Groups) under it.
        let signatures = lines.indices.filter { index in
            lines[index] == "-- " || (fromHTML && lines[index].wholeMatch(of: /-- */) != nil)
        }
        let signature = signatures.first
        let history = [
            // A quote up to a signature or a list footer under it, or a quote to the end.
            (signatures + [lines.count]).compactMap { end in
                trailingAttributionStart(in: lines, before: end, allowingNoQuote: afterRemovedQuote)
            }.min(),
            findingOutlookHeader ? outlookHeaderStart(in: lines) : nil,
        ].compactMap { $0 }.min()

        // A forward marker above the history is the start of a forward. One
        // in the history is an earlier message's: Outlook does not quote it.
        let forward = lines[..<(history ?? lines.count)].contains { !isQuoted($0) && isForwardMarker($0) }
        guard !forward else { return .forward }
        // Gmail puts the signature above the quote, so answers written
        // between the quoted lines are under it: then it does not start the
        // cut. An answer is an unquoted line under a quoted line, before the
        // history or the next `-- ` line.
        // A quoted forward that is not history is one the HTML pass kept
        // (an Apple Mail forward with an edited subject), so it stays too.
        let signatureCut = signature.flatMap { start -> Int? in
            guard !keptAnswers else { return nil }
            let end = min(history ?? lines.count, signatures.dropFirst().first ?? lines.count)
            guard start < end else { return start }
            var quoteSeen = false
            for line in lines[(start + 1)..<end] {
                if isQuoted(line) {
                    if isForwardMarker(line.drop { $0 == ">" || $0 == " " }) {
                        return nil
                    }
                    quoteSeen = true
                } else if quoteSeen && !isBlank(line) {
                    return nil
                }
            }
            return start
        }
        guard let cut = [signatureCut, history].compactMap({ $0 }).min() else { return .noMarker }
        let kept = BodyCleanup.clean(lines[..<cut].joined(separator: "\n"))
        return kept.isEmpty ? .allHistory : .trimmed(kept)
    }

    /// Whether a line is quoted: it starts with `>`, after any spaces.
    static func isQuoted(_ line: Substring) -> Bool {
        line.first { $0 != " " } == ">"
    }

    static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// The first line of the first attribution before `end` that only quoted
    /// and blank lines follow, up to `end`: an unquoted one
    /// (`attributionStart(in:endingAt:)`), or a quoted one that starts a quote
    /// (`isQuotedAttribution(in:at:)`).
    ///
    /// - Parameter allowingNoQuote: Whether the attribution may also have only
    ///   blank lines after it.
    static func trailingAttributionStart(in lines: [Substring], before end: Int, allowingNoQuote: Bool) -> Int? {
        for index in 0..<end {
            let start: Int
            if let unquoted = attributionStart(in: lines, endingAt: index) {
                start = unquoted
            } else if isQuotedAttribution(in: lines, at: index) {
                start = index
            } else {
                continue
            }
            let after = lines[(index + 1)..<end]
            guard after.allSatisfy({ isQuoted($0) || isBlank($0) }) else { continue }
            if allowingNoQuote || after.contains(where: isQuoted) {
                return start
            }
        }
        return nil
    }

    /// The first line of the attribution that ends at `lines[index]`, or nil
    /// when that line ends none.
    static func attributionStart(in lines: [Substring], endingAt index: Int) -> Int? {
        let line = lines[index]
        guard !isQuoted(line) else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.wholeMatch(of: /-+ *On\s.*\swrote *-+/.ignoresCase()) != nil
            || text.wholeMatch(of: /On\s.*\swrote:/.ignoresCase()) != nil {
            return index
        }
        // A plain-text reply wraps a long attribution:
        // "On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com>" / "wrote:".
        guard index > 0, text.wholeMatch(of: /(?:.*\s)?wrote:/.ignoresCase()) != nil else { return nil }
        let previous = lines[index - 1]
        guard !isQuoted(previous),
              previous.trimmingCharacters(in: .whitespaces).prefixMatch(of: /On\s/.ignoresCase()) != nil
        else { return nil }
        return index - 1
    }

    /// Whether `lines[index]` is a quoted attribution that starts a quote:
    /// iPhone and Apple Mail quote their attribution with the message
    /// (`> On <date>, <name> wrote:`), so it is the first line of the quote.
    static func isQuotedAttribution(in lines: [Substring], at index: Int) -> Bool {
        let line = lines[index]
        guard isQuoted(line), index == 0 || !isQuoted(lines[index - 1]) else { return false }
        let text = line.drop { $0 == " " }.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.wholeMatch(of: /On\s.*\swrote:/.ignoresCase()) != nil
    }

    /// The most label lines read under a `From:` line.
    static let maxHeaderLabels = 6

    /// The first line of the first Outlook header block (with the separator
    /// line above it), or nil when there is none.
    static func outlookHeaderStart(in lines: [Substring]) -> Int? {
        for index in lines.indices where headerLabel(lines[index]) == "from" {
            var labels: Set<String> = []
            var next = index + 1
            while next < lines.count, labels.count < maxHeaderLabels {
                if isBlank(lines[next]) {
                    next += 1
                    continue
                }
                guard let label = headerLabel(lines[next]) else { break }
                labels.insert(label)
                next += 1
            }
            guard labels.contains("subject"), labels.contains("sent") || labels.contains("date") else { continue }

            var above = index - 1
            while above >= 0, isBlank(lines[above]) {
                above -= 1
            }
            return above >= 0 && isHeaderSeparator(lines[above]) ? above : index
        }
        return nil
    }

    /// The label of a header line such as `From: Jane` or `**Sent:** Friday`,
    /// in lowercase, or nil when the line is not one.
    static func headerLabel(_ line: Substring) -> String? {
        let label = /\s*[*_]{0,2}(from|sent|date|to|cc|subject)[*_]{0,2}\s*:[*_]{0,2}(?:\s|$)/.ignoresCase()
        return line.prefixMatch(of: label).map { $0.output.1.lowercased() }
    }

    /// Whether a line is the separator that Outlook puts above its header block.
    static func isHeaderSeparator(_ line: Substring) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.wholeMatch(of: /_{3,}|-{3,}|\*{3,}|(?:\* ){2,}\*|-+ *original message *-+/.ignoresCase()) != nil
    }

    // MARK: - HTML

    /// What `removeHistory(fromHTMLParts:inReply:)` removed.
    struct Removal: Equatable {
        /// A quote, its attribution, or Outlook's header and what follows it.
        var quote = false
        var signature = false
        /// Not a removal: the walk stopped at text inside a reply's quote
        /// container (answers between quoted lines, or under Zoho's header),
        /// so that text is the sender's and stays.
        var keptAnswers = false
        /// Not a removal: the walk stopped at a quote that starts a forward.
        var keptForward = false

        var any: Bool { quote || signature }

        static func + (lhs: Removal, rhs: Removal) -> Removal {
            Removal(
                quote: lhs.quote || rhs.quote,
                signature: lhs.signature || rhs.signature,
                keptAnswers: lhs.keptAnswers || rhs.keptAnswers,
                keptForward: lhs.keptForward || rhs.keptForward
            )
        }
    }

    /// Removes the quoted history and signature at the end of `documents`,
    /// the HTML parts of one body in order, before they become Markdown. It
    /// starts with the last part, and moves to the part before only when
    /// nothing is left of the later one.
    ///
    /// These elements are removed, each only when nothing but other such
    /// elements and blank space follows it:
    /// - Gmail: `blockquote class="gmail_quote"` inside the `div.gmail_quote`
    ///   around a reply's quote, its attribution (class `gmail_attr`), and
    ///   the signature (class `gmail_signature` or `gmail_signature_prefix`,
    ///   the `-- ` line). The `div.gmail_quote` is searched like any other
    ///   element, because Gmail puts answers written between the quoted
    ///   lines in it. A `blockquote.gmail_quote` outside it is one that the
    ///   sender wrote (Gmail's Quote button), so it is kept.
    /// - Zoho Mail: `blockquote#blockquote_zmail` and its header (id
    ///   `Zm-_Id_-Sgn1`) inside `div.zmail_extra`, which is searched like
    ///   Gmail's.
    /// - Apple Mail and Thunderbird: `blockquote type="cite"` (Apple Mail puts
    ///   the attribution in one too), class `moz-cite-prefix` (Thunderbird's
    ///   attribution), and class `moz-signature`.
    /// - New Outlook: id `mail-editor-reference-message-container`.
    /// - Any app: a hidden element (`display: none`), such as Superhuman's
    ///   tracking image or Zoho's separator line. A reader never sees it, so
    ///   it is removed without counting as history.
    ///
    /// A quote or quote container (`div.gmail_quote`, `div.zmail_extra`)
    /// that starts a forward (`isForwardMarker(_:)`) counts as content: it is
    /// kept whole, and so is everything before it. In a reply, such a quote
    /// is the forward that the reply quotes, so it is removed like any quote,
    /// and such a container is searched like any element. (The text pass
    /// still cuts a quoted forward under an English attribution.)
    ///
    /// A quote container with no marked attribution (`isMarkedAttribution(_:)`)
    /// whose quote was removed, and that holds only one line of text after
    /// that (no image), is removed too: that line is an attribution without
    /// a class (Gmail's older markup, Superhuman). In a container with a
    /// marked attribution, a line left above it is the sender's.
    ///
    /// Outlook's reply header, `div#divRplyFwdMsg`, is removed with everything
    /// after it, and with the `<hr>` just above it: Outlook does not put the
    /// message it quotes in a blockquote. A header inside another app's
    /// quote is part of that quote, so it is not looked for there.
    ///
    /// - Parameter inReply: Whether the message is a reply (`isReply(subject:)`).
    static func removeHistory(fromHTMLParts documents: [HTMLDocument], inReply: Bool = false) -> Removal {
        var removal = Removal()
        for document in documents.reversed() {
            let root = contentRoot(of: document)
            removal.quote = removeOutlookHistory(in: root) || removal.quote
            let tail = removeTrailingHistory(in: root, inReply: inReply, depth: 0)
            removal = removal + tail.removal
            if tail.contentLeft {
                break
            }
        }
        return removal
    }

    /// Whether `documents` still have Zoho's marked header (id
    /// `Zm-_Id_-Sgn1`) in Zoho's quote container. Read it after
    /// `removeHistory`, which removes the header when nothing follows it:
    /// a header that is left is either above the sender's text or above
    /// something the HTML pass stopped at (a footer, a reply under the
    /// quote), and in English it reads like Outlook's header block.
    static func hasZohoHeader(in documents: [HTMLDocument]) -> Bool {
        documents.contains { document in
            path(in: contentRoot(of: document)) { element in
                isQuoteContainer(element) && element.children.contains { node in
                    (node as? DOMElement).flatMap { attribute("id", of: $0) }.map(containerAttributionIDs.contains) == true
                }
            } != nil
        }
    }

    /// The element that `HTMLDocument.markdown()` converts: the `<html>`
    /// element, so that a footer a mail server put after `</html>` does not
    /// hide the end of the body.
    static func contentRoot(of document: HTMLDocument) -> DOMElement {
        let root = document.root
        guard root.name.lowercased() == "document",
              let html = root.children.compactMap({ $0 as? DOMElement }).first(where: { $0.name.lowercased() == "html" })
        else { return root }
        return html
    }

    /// The classes of an attribution, which is removed like a quote.
    static let attributionClasses: Set<String> = ["gmail_attr", "moz-cite-prefix"]
    /// The classes of Gmail's and Zoho's element around the attribution and the quote.
    static let quoteContainerClasses: Set<String> = ["gmail_quote", "gmail_quote_container", "zmail_extra"]
    /// The id of the attribution (the From/Date/Subject header) that Zoho puts in its container.
    static let containerAttributionIDs: Set<String> = ["Zm-_Id_-Sgn1"]
    /// The id of the quote that Zoho puts in its container.
    static let containerQuoteIDs: Set<String> = ["blockquote_zmail"]
    static let signatureClasses: Set<String> = ["gmail_signature", "gmail_signature_prefix", "moz-signature"]
    static let quoteIDs: Set<String> = ["mail-editor-reference-message-container"]
    static let outlookHeaderID = "divRplyFwdMsg"

    /// The elements that hold no text of the body.
    static let nonContentTags: Set<String> = ["head", "title", "style", "script", "meta", "link"]

    /// The deepest level the end of a body is searched. Mail apps nest only a
    /// few levels; a deeper element counts as content, so that the search
    /// never runs out of stack.
    static let maxDepth = 100

    /// Removes the history elements at the end of `element`, from its last
    /// child back to the first child with content. Returns what it removed,
    /// and whether content is left.
    ///
    /// - Parameter inReply: Whether a quote that starts a forward is removed
    ///   too (see `removeHistory(fromHTMLParts:inReply:)`).
    static func removeTrailingHistory(in element: DOMElement, inReply: Bool, depth: Int) -> (removal: Removal, contentLeft: Bool) {
        var removal = Removal()
        for index in element.children.indices.reversed() {
            guard let child = element.children[index] as? DOMElement else {
                if hasContent(element.children[index]) {
                    return (removal, true)
                }
                continue
            }
            if nonContentTags.contains(child.name) {
                continue
            }
            if isHidden(child) {
                element.children.remove(at: index)
                continue
            }
            if child.name == "img" {
                return (removal, true)
            }
            if !inReply && (isQuote(child, in: element) || isQuoteContainer(child)) && startsForward(child) {
                removal.keptForward = true
                return (removal, true)
            }
            if isSignature(child) {
                element.children.remove(at: index)
                removal.signature = true
                continue
            }
            if isQuote(child, in: element) {
                element.children.remove(at: index)
                removal.quote = true
                continue
            }
            if depth >= maxDepth {
                if hasContent(child) {
                    return (removal, true)
                }
                continue
            }
            // Taken before the walk, which removes a marked attribution.
            let hasMarkedAttribution = isQuoteContainer(child) && child.children.contains { node in
                (node as? DOMElement).map(isMarkedAttribution) == true
            }
            let inner = removeTrailingHistory(in: child, inReply: inReply, depth: depth + 1)
            removal = removal + inner.removal
            if inner.contentLeft {
                // Gmail's older markup and Superhuman put the attribution
                // in the container with no class, as bare text or in a
                // plain div. When the quote under it is gone and only one
                // line is left, it is that attribution: an answer written in
                // the container adds a line (or an earlier quote does). A
                // container with a marked attribution has none of these, so
                // a line left above that attribution is the sender's.
                if isQuoteContainer(child) && !hasMarkedAttribution && inner.removal.quote && isOneLine(child) {
                    element.children.remove(at: index)
                    continue
                }
                // What is left in the container is the sender's text, unless
                // the walk stopped at a forward, or at a quote it does not
                // know (the text pass may still find that one).
                if isQuoteContainer(child), !inner.removal.keptForward,
                   let last = child.children.last(where: hasContent), (last as? DOMElement)?.name != "blockquote" {
                    removal.keptAnswers = true
                }
                return (removal, true)
            }
        }
        return (removal, false)
    }

    /// Whether `element` is an attribution with a mark: class `gmail_attr`
    /// or `moz-cite-prefix`, or Zoho's header id.
    static func isMarkedAttribution(_ element: DOMElement) -> Bool {
        !classes(of: element).isDisjoint(with: attributionClasses)
            || attribute("id", of: element).map(containerAttributionIDs.contains) == true
    }

    /// Whether `element` holds exactly one line of text, and no image.
    static func isOneLine(_ element: DOMElement) -> Bool {
        var pending: [DOMNode] = element.children
        while let node = pending.popLast() {
            if let child = node as? DOMElement {
                if child.name == "img" {
                    return false
                }
                pending.append(contentsOf: child.children)
            }
        }
        return element.text().split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }.count == 1
    }

    /// Whether `element` is a signature that `removeHistory(fromHTMLParts:inReply:)` removes.
    static func isSignature(_ element: DOMElement) -> Bool {
        !classes(of: element).isDisjoint(with: signatureClasses)
    }

    /// Whether `element` is a quote (or its attribution) that
    /// `removeHistory(fromHTMLParts:inReply:)` removes, unless it starts a
    /// forward in a message that is not a reply.
    ///
    /// - Parameter parent: The element that holds `element`. Gmail's and
    ///   Zoho's quotes count only inside their quote container
    ///   (`isQuoteContainer(_:)`). Nil counts as inside one.
    static func isQuote(_ element: DOMElement, in parent: DOMElement?) -> Bool {
        let classes = classes(of: element)
        let id = attribute("id", of: element)
        let isBlockquote = element.name == "blockquote"
        let inContainer = parent.map(isQuoteContainer) ?? true
        return !classes.isDisjoint(with: attributionClasses)
            || (inContainer && isBlockquote && classes.contains("gmail_quote"))
            || (inContainer && id.map { containerQuoteIDs.contains($0) || containerAttributionIDs.contains($0) } == true)
            || (isBlockquote && attribute("type", of: element)?.lowercased() == "cite")
            || id.map(quoteIDs.contains) == true
    }

    /// Whether `element` is Gmail's or Zoho's element around an attribution
    /// and a quote, which is searched, not removed whole.
    static func isQuoteContainer(_ element: DOMElement) -> Bool {
        element.name != "blockquote" && !classes(of: element).isDisjoint(with: quoteContainerClasses)
    }

    /// Whether `element` is hidden by its inline style (`display: none`).
    static func isHidden(_ element: DOMElement) -> Bool {
        attribute("style", of: element)?.contains(/display\s*:\s*none/.ignoresCase()) == true
    }

    static func classes(of element: DOMElement) -> Set<String> {
        Set(attribute("class", of: element)?.split(whereSeparator: \.isWhitespace).map(String.init) ?? [])
    }

    /// Whether the first line of text in `element` is a forward marker.
    static func startsForward(_ element: DOMElement) -> Bool {
        let firstLine = element.text().split(whereSeparator: \.isNewline).first { line in
            !line.allSatisfy(\.isWhitespace)
        }
        return firstLine.map(isForwardMarker) ?? false
    }

    /// Removes Outlook's reply header, everything after it in the document,
    /// and the `<hr>` just above it. Returns whether there was one outside
    /// other apps' quotes (`isQuote(_:in:)`, `isQuoteContainer(_:)`).
    static func removeOutlookHistory(in root: DOMElement) -> Bool {
        let isHeader = { (element: DOMElement) in attribute("id", of: element) == outlookHeaderID }
        let isOtherQuote = { (element: DOMElement) in isQuote(element, in: nil) || isQuoteContainer(element) }
        guard let path = path(in: root, to: isHeader, skipping: isOtherQuote),
              let header = path.last
        else { return false }
        for (level, step) in path.enumerated() {
            // The header itself goes, and every node after the header or after one of its ancestors.
            let first = level == path.count - 1 ? step.index : step.index + 1
            step.parent.children.removeSubrange(first...)
        }
        let parent = header.parent
        while let last = parent.children.last, !(last is DOMElement), !hasContent(last) {
            parent.children.removeLast()
        }
        if let rule = parent.children.last as? DOMElement, rule.name == "hr" {
            parent.children.removeLast()
        }
        return true
    }

    /// The path from `root` to the first element in document order that
    /// `matches`: each step is a parent and the index of the next element in
    /// it. Nil when no element matches.
    ///
    /// - Parameter skips: The elements whose subtree is not searched.
    static func path(
        in root: DOMElement,
        to matches: (DOMElement) -> Bool,
        skipping skips: (DOMElement) -> Bool = { _ in false }
    ) -> [(parent: DOMElement, index: Int)]? {
        var pending: [(element: DOMElement, path: [(parent: DOMElement, index: Int)])] = [(root, [])]
        while let entry = pending.popLast() {
            if !entry.path.isEmpty && matches(entry.element) {
                return entry.path
            }
            if !entry.path.isEmpty && skips(entry.element) {
                continue
            }
            // Reversed, so that the first child comes off the stack first.
            for (index, child) in entry.element.children.enumerated().reversed() {
                if let child = child as? DOMElement {
                    pending.append((child, entry.path + [(entry.element, index)]))
                }
            }
        }
        return nil
    }

    /// Whether `node` holds text that is not blank, or an image.
    static func hasContent(_ node: DOMNode) -> Bool {
        var pending: [DOMNode] = [node]
        while let node = pending.popLast() {
            if let element = node as? DOMElement {
                if element.name == "img" {
                    return true
                }
                if !nonContentTags.contains(element.name) {
                    pending.append(contentsOf: element.children)
                }
            } else if !node.text().allSatisfy(\.isWhitespace) {
                return true
            }
        }
        return false
    }

    /// The value of the attribute `name`, or nil when the element has none.
    static func attribute(_ name: String, of element: DOMElement) -> String? {
        element.attributes[name] as? String
    }
}
