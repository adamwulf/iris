import Foundation

/// A draft ready to save: the headers iris chooses, the two body parts, and
/// the attachments. SwiftMail adds the rest when it writes the message: Date
/// (now), a Message-ID for a new reply, and the multipart/alternative structure, inside
/// multipart/mixed with the attachments when there are any.
public struct DraftMessage: Sendable, Equatable {
    public let from: MailAddress
    public let to: [MailAddress]
    public let cc: [MailAddress]
    public let bcc: [MailAddress]
    public let replyTo: [MailAddress]
    /// Updating a draft keeps its Message-ID; a new reply gets a new one.
    public let messageID: String?
    public let subject: String
    /// The message ID that this draft replies to, with angle brackets. Nil when
    /// the original has no Message-ID.
    public let inReplyTo: String?
    /// The message IDs of the thread, oldest first, with angle brackets.
    public let references: [String]
    /// The text/plain part: the reply and the quote, as Markdown.
    public let markdown: String
    /// The text/html part: the reply's Markdown rendered, then the quote
    /// (see `ReplyComposer.quotation(of:timeZone:)`).
    public let html: String
    /// Files attached to a new reply, or the original draft's attachments,
    /// including inline parts, when updating.
    public let attachments: [DraftAttachment]

    /// Threading values from a draft being updated, refolded for serialization,
    /// including all In-Reply-To IDs and comments. New replies use `threadingHeaders`.
    let preservedThreadingHeaders: [String: String]?

    init(
        from: MailAddress, to: [MailAddress], cc: [MailAddress],
        bcc: [MailAddress] = [], replyTo: [MailAddress] = [], messageID: String? = nil,
        subject: String, inReplyTo: String?, references: [String],
        markdown: String, html: String, attachments: [DraftAttachment],
        preservedThreadingHeaders: [String: String]? = nil
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.messageID = messageID
        self.subject = subject
        self.inReplyTo = inReplyTo
        self.references = references
        self.markdown = markdown
        self.html = html
        self.attachments = attachments
        self.preservedThreadingHeaders = preservedThreadingHeaders
    }

    /// The longest header line iris writes, as RFC 5322 (section 2.1.1) asks.
    static let maxLineLength = 78

    /// `In-Reply-To` and `References`, for SwiftMail's `additionalHeaders`.
    /// Empty when there is nothing to reply to.
    var threadingHeaders: [String: String] {
        if let preservedThreadingHeaders { return preservedThreadingHeaders }
        var headers: [String: String] = [:]
        if let inReplyTo {
            headers["In-Reply-To"] = inReplyTo
        }
        if !references.isEmpty {
            headers["References"] = Self.folded(references, headerName: "References")
        }
        return headers
    }

    /// `ids` with a space between them, and a fold (CRLF and a space) before an
    /// ID that would take the line past `maxLineLength`. SwiftMail writes
    /// header values unchanged, so a long References header is folded here.
    /// An ID longer than a line stays whole on its own line.
    static func folded(_ ids: [String], headerName: String) -> String {
        var value = ""
        // The first line starts with "References: ".
        var lineLength = headerName.utf8.count + 2
        for id in ids {
            if value.isEmpty {
                value = id
                lineLength += id.utf8.count
            } else if lineLength + 1 + id.utf8.count > maxLineLength {
                value += "\r\n " + id
                lineLength = 1 + id.utf8.count
            } else {
                value += " " + id
                lineLength += 1 + id.utf8.count
            }
        }
        return value
    }

    /// Refold an already-unfolded header at its existing spaces or tabs. Unlike
    /// `folded(_:headerName:)` for IDs, this preserves every character of the
    /// value, including comments and their whitespace. Removing just the added
    /// CRLFs restores the input exactly. Unbreakable oversized values are refused.
    static func refolded(_ value: String, headerName: String) throws -> String {
        var result = ""
        var lineLength = headerName.utf8.count + 2
        var whitespace = ""
        var word = ""
        func appendWord() throws {
            let chunk = whitespace + word
            if !whitespace.isEmpty && lineLength + chunk.utf8.count > maxLineLength {
                result += "\r\n"
                lineLength = 0
            }
            guard lineLength + chunk.utf8.count <= 998 else {
                throw IrisError.draftNotPreserved(reason: "a threading header contains text too long to fold safely")
            }
            result += chunk
            lineLength += chunk.utf8.count
            whitespace = ""
            word = ""
        }
        for character in value {
            if character == " " || character == "\t" {
                if !word.isEmpty { try appendWord() }
                whitespace.append(character)
            } else {
                word.append(character)
            }
        }
        try appendWord()
        return result
    }
}
