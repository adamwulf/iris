import Foundation

/// A draft ready to save: the headers iris chooses and the two body parts.
/// SwiftMail adds the rest when it writes the message: Date (now), a new
/// Message-ID, and the multipart/alternative structure.
public struct DraftMessage: Sendable, Equatable {
    public let from: MailAddress
    public let to: [MailAddress]
    public let cc: [MailAddress]
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

    /// The longest header line iris writes, as RFC 5322 (section 2.1.1) asks.
    static let maxLineLength = 78

    /// `In-Reply-To` and `References`, for SwiftMail's `additionalHeaders`.
    /// Empty when there is nothing to reply to.
    var threadingHeaders: [String: String] {
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
}
