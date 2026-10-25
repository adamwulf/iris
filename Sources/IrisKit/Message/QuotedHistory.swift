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
        var text = subject ?? ""
        if let tags = text.prefixMatch(of: /\s*(?:\[[^\]]*\]\s*)*/) {
            text.removeSubrange(tags.range)
        }
        return text.prefixMatch(of: /(?:fwd|fw)\s*:/.ignoresCase()) != nil
    }

    /// Whether `line` starts a forwarded message: Gmail's
    /// `---------- Forwarded message ---------`, Thunderbird's
    /// `-------- Forwarded Message --------`, or Apple Mail's `Begin forwarded message:`.
    static func isForwardMarker(_ line: some StringProtocol) -> Bool {
        let text = String(line).trimmingCharacters(in: .whitespaces)
        return text.wholeMatch(of: /-+ *forwarded message *-+/.ignoresCase()) != nil
            || text.wholeMatch(of: /begin forwarded message:/.ignoresCase()) != nil
    }

    // MARK: - Text

    /// `text`, a cleaned body (plain text, or Markdown from HTML), without the
    /// quoted history and signature at its end. Nil when it has none, when it
    /// has an unquoted forward marker (`isForwardMarker(_:)`), or when nothing
    /// would be left.
    ///
    /// The cut starts at the first of these:
    /// - The signature separator, a line that is exactly `-- `.
    /// - An attribution line, `On <date>, <name> wrote:` (it may wrap onto a
    ///   second line) or Zoho's `---- On <date> <name> wrote ----`, with only
    ///   quoted (`>`) and blank lines after it, at least one of them quoted,
    ///   up to the signature or the end.
    /// - Outlook's header block: a `From:` line with `Sent:` (or `Date:`) and
    ///   `Subject:` among the label lines under it (the labels may be bold),
    ///   from the separator line above it when there is one (`_____`,
    ///   `-----Original Message-----`, or a thematic break). Outlook does not
    ///   quote the message under it, so the cut runs to the end.
    ///
    /// - Parameter afterRemovedQuote: Whether an HTML quote was removed from
    ///   the end. Then an attribution line with nothing after it starts the
    ///   cut too: it was the removed quote's (older Apple Mail puts it above
    ///   the `blockquote`).
    static func trimmedText(_ text: String, afterRemovedQuote: Bool = false) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.contains(where: { !isQuoted($0) && isForwardMarker($0) }) else { return nil }

        let signature = lines.firstIndex { $0 == "-- " }
        let starts = [
            signature,
            trailingAttributionStart(in: lines, before: signature ?? lines.count, allowingNoQuote: afterRemovedQuote),
            outlookHeaderStart(in: lines),
        ].compactMap { $0 }
        guard let cut = starts.min() else { return nil }
        let kept = BodyCleanup.clean(lines[..<cut].joined(separator: "\n"))
        return kept.isEmpty ? nil : kept
    }

    /// Whether a line is quoted: it starts with `>`, after any spaces.
    static func isQuoted(_ line: Substring) -> Bool {
        line.first { $0 != " " } == ">"
    }

    static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// The first line of the first attribution before `end` that only quoted
    /// and blank lines follow, up to `end`.
    ///
    /// - Parameter allowingNoQuote: Whether the attribution may also have only
    ///   blank lines after it.
    static func trailingAttributionStart(in lines: [Substring], before end: Int, allowingNoQuote: Bool) -> Int? {
        for index in 0..<end {
            guard let start = attributionStart(in: lines, endingAt: index) else { continue }
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

    /// Removes the quoted history and signature at the end of `documents`,
    /// the HTML parts of one body in order, before they become Markdown. It
    /// starts with the last part, and moves to the part before only when
    /// nothing is left of the later one. Returns whether anything was removed.
    ///
    /// These elements are removed, each only when nothing but other such
    /// elements and blank space follows it, except a quote that starts a
    /// forward (`isForwardMarker(_:)`):
    /// - Gmail: class `gmail_quote` (the attribution and the quote) and
    ///   `gmail_signature` or `gmail_signature_prefix` (the `-- ` line).
    /// - Apple Mail and Thunderbird: `blockquote type="cite"` (Apple Mail puts
    ///   the attribution in one too), class `moz-cite-prefix` (Thunderbird's
    ///   attribution), and class `moz-signature`.
    /// - New Outlook: id `mail-editor-reference-message-container`.
    ///
    /// Outlook's reply header, `div#divRplyFwdMsg`, is removed with everything
    /// after it, wherever it is, and with the `<hr>` just above it: Outlook
    /// does not put the message it quotes in a blockquote.
    static func removeHistory(fromHTMLParts documents: [HTMLDocument]) -> Bool {
        var removed = false
        for document in documents.reversed() {
            let root = contentRoot(of: document)
            let removedOutlookHistory = removeOutlookHistory(in: root)
            let tail = removeTrailingHistory(in: root, depth: 0)
            removed = removed || removedOutlookHistory || tail.removed
            if tail.contentLeft {
                break
            }
        }
        return removed
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

    static let quoteClasses: Set<String> = ["gmail_quote", "gmail_quote_container", "moz-cite-prefix"]
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
    /// child back to the first child with content. Returns whether it removed
    /// any, and whether content is left.
    static func removeTrailingHistory(in element: DOMElement, depth: Int) -> (removed: Bool, contentLeft: Bool) {
        var removed = false
        for index in element.children.indices.reversed() {
            guard let child = element.children[index] as? DOMElement else {
                if hasContent(element.children[index]) {
                    return (removed, true)
                }
                continue
            }
            if nonContentTags.contains(child.name) {
                continue
            }
            if child.name == "img" {
                return (removed, true)
            }
            if isHistory(child) {
                element.children.remove(at: index)
                removed = true
                continue
            }
            if depth >= maxDepth {
                if hasContent(child) {
                    return (removed, true)
                }
                continue
            }
            let inner = removeTrailingHistory(in: child, depth: depth + 1)
            removed = removed || inner.removed
            if inner.contentLeft {
                return (removed, true)
            }
        }
        return (removed, false)
    }

    /// Whether `element` is a quote or a signature that `removeHistory(fromHTMLParts:)` removes.
    static func isHistory(_ element: DOMElement) -> Bool {
        let classes = Set(attribute("class", of: element)?.split(whereSeparator: \.isWhitespace).map(String.init) ?? [])
        if !classes.isDisjoint(with: signatureClasses) {
            return true
        }
        let isQuote = !classes.isDisjoint(with: quoteClasses)
            || (element.name == "blockquote" && attribute("type", of: element)?.lowercased() == "cite")
            || attribute("id", of: element).map(quoteIDs.contains) == true
        return isQuote && !startsForward(element)
    }

    /// Whether the first line of text in `element` is a forward marker.
    static func startsForward(_ element: DOMElement) -> Bool {
        let firstLine = element.text().split(whereSeparator: \.isNewline).first { line in
            !line.allSatisfy(\.isWhitespace)
        }
        return firstLine.map(isForwardMarker) ?? false
    }

    /// Removes Outlook's reply header, everything after it in the document,
    /// and the `<hr>` just above it. Returns whether there was one.
    static func removeOutlookHistory(in root: DOMElement) -> Bool {
        guard let path = path(in: root, to: { attribute("id", of: $0) == outlookHeaderID }),
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
    static func path(
        in root: DOMElement,
        to matches: (DOMElement) -> Bool
    ) -> [(parent: DOMElement, index: Int)]? {
        var pending: [(element: DOMElement, path: [(parent: DOMElement, index: Int)])] = [(root, [])]
        while let entry = pending.popLast() {
            if !entry.path.isEmpty && matches(entry.element) {
                return entry.path
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
