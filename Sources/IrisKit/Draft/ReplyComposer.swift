import Foundation

/// Builds the reply that `iris draft` saves, from the decoded original. It
/// talks to no server, so the tests cover all of it.
public enum ReplyComposer {
    /// A reply to `original` from `from`, with `body` (Markdown) as its text.
    ///
    /// - Parameters:
    ///   - username: The account's username. When it is an address, it is
    ///     yours, as `from` is: a message from it is your own, and `replyAll`
    ///     leaves it out of Cc.
    ///   - replyAll: Also Cc the original's To and Cc recipients.
    ///   - quote: Add the original's body after the reply, as a Markdown quote.
    ///   - timeZone: The zone for the date in the quote's first line. Tests pass a fixed zone.
    public static func reply(
        to original: MessageDocument,
        body: String,
        from: MailAddress,
        username: String,
        replyAll: Bool,
        quote: Bool,
        timeZone: TimeZone = .current
    ) -> DraftMessage {
        let me = [from.address] + (username.contains("@") ? [username] : [])
        let to = recipients(of: original, me: me)
        let cc = replyAll ? ccRecipients(of: original, to: to, me: me) : []

        var markdown = BodyCleanup.normalizeLineEndings(body)
        while markdown.last?.isWhitespace == true {
            markdown.removeLast()
        }
        var html = MarkdownHTML.html(fromMarkdown: markdown)
        if quote, let quotation = quotation(of: original, timeZone: timeZone) {
            markdown += "\n\n" + quotation.text
            html += quotation.html
        }

        let (inReplyTo, references) = threading(of: original)
        return DraftMessage(
            from: from,
            to: to,
            cc: cc,
            subject: subject(replyingTo: original.subject),
            inReplyTo: inReplyTo,
            references: references,
            markdown: markdown,
            html: html
        )
    }

    /// `Re: <subject>`, with no second `Re:` when the subject starts with one in any case.
    static func subject(replyingTo subject: String?) -> String {
        let subject = (subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if subject.lowercased().hasPrefix("re:") {
            return subject
        }
        return subject.isEmpty ? "Re:" : "Re: \(subject)"
    }

    /// Who the reply goes to: the original's Reply-To, else its From.
    ///
    /// When you sent the original (its first From address is one of `me`, the
    /// user's own addresses), as for a message in Sent, the reply goes to the
    /// people you wrote to instead, as mail apps reply: the original's
    /// Reply-To when it names someone but you (a contact form sends From you,
    /// Reply-To the visitor), else its To recipients, both without you and
    /// without repeats. When neither names anyone but you, the first rule applies.
    static func recipients(of original: MessageDocument, me: [String]) -> [MailAddress] {
        if let sender = original.from.first, me.contains(where: { $0.lowercased() == sender.address.lowercased() }) {
            for candidates in [original.replyTo, original.to] {
                let others = unique(candidates, excluding: me)
                if !others.isEmpty {
                    return others
                }
            }
        }
        return original.replyTo.isEmpty ? original.from : original.replyTo
    }

    /// The original's To and Cc recipients without the addresses in `to` and
    /// in `me` (the user's own addresses), and without repeats.
    static func ccRecipients(of original: MessageDocument, to: [MailAddress], me: [String]) -> [MailAddress] {
        unique(original.to + original.cc, excluding: to.map(\.address) + me)
    }

    /// `addresses` without the ones in `excluded` and without repeats; the
    /// first copy wins. Addresses are compared ignoring case.
    private static func unique(_ addresses: [MailAddress], excluding excluded: [String]) -> [MailAddress] {
        var seen = Set(excluded.map { $0.lowercased() })
        return addresses.filter { address in
            seen.insert(address.address.lowercased()).inserted
        }
    }

    /// In-Reply-To and References (RFC 5322, section 3.6.4): the original's
    /// Message-ID, and the original's References (else its In-Reply-To)
    /// followed by that ID. Both are left out when the original has no Message-ID.
    static func threading(of original: MessageDocument) -> (inReplyTo: String?, references: [String]) {
        guard let messageID = original.messageID, isWritable(messageID) else {
            return (nil, [])
        }
        let earlier = original.references.isEmpty ? original.inReplyTo.map { [$0] } ?? [] : original.references
        return (messageID, earlier.filter(isWritable) + [messageID])
    }

    /// Whether a message ID can go into a header as it is. iris writes these
    /// headers itself, so an ID with white space or a control character (which
    /// a valid ID never has) could break the header or add one.
    static func isWritable(_ messageID: String) -> Bool {
        !messageID.unicodeScalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
        }
    }

    /// The quote of `original` for both parts. Nil when the original has no body.
    ///
    /// The text part is the attribution line, then the original's body with
    /// `> ` before each line and `>` for an empty line. The HTML part is the
    /// attribution line, then the body in a `<blockquote type="cite">`, as
    /// Apple Mail quotes: the Markdown rendered when the body came from an
    /// HTML part, else the plain text escaped line by line. A plain-text body
    /// is never read as Markdown, where a `-- ` signature line would make the
    /// line above it a heading.
    static func quotation(of original: MessageDocument, timeZone: TimeZone) -> (text: String, html: String)? {
        guard !original.body.isEmpty else {
            return nil
        }
        let attribution = attribution(of: original, timeZone: timeZone)
        let lines = original.body.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? ">" : "> " + line
        }
        let quoted = original.bodySource == .html
            ? MarkdownHTML.html(fromMarkdown: original.body)
            : MarkdownHTML.html(fromPlainText: original.body)
        let html = "<p>\(MarkdownHTML.escaped(attribution))</p>\n<blockquote type=\"cite\">\n\(quoted)</blockquote>\n"
        return (([attribution] + lines).joined(separator: "\n"), html)
    }

    /// `On <date>, <sender> wrote:`, or `<sender> wrote:` when the original has no date.
    static func attribution(of original: MessageDocument, timeZone: TimeZone) -> String {
        let sender = original.from.first?.displayName ?? "someone"
        guard let date = original.date else {
            return "\(sender) wrote:"
        }
        return "On \(DateText.string(from: date, timeZone: timeZone, showingZone: true)), \(sender) wrote:"
    }
}
