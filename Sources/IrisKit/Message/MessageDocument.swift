import Foundation

/// One decoded email, ready for `iris show`: the headers people read, the body
/// as Markdown, and a list of the other parts. It never holds attachment bytes.
public struct MessageDocument: Sendable, Equatable, Encodable {
    /// The `Message-ID` with angle brackets, for example `<abc@example.com>`.
    public let messageID: String?
    public let subject: String?
    public let from: [MailAddress]
    public let to: [MailAddress]
    public let cc: [MailAddress]
    public let replyTo: [MailAddress]
    /// The `Date` header, set by the sender.
    public let date: Date?
    /// The first message ID in `In-Reply-To`, with angle brackets.
    public let inReplyTo: String?
    /// The message IDs in `References`, oldest first, with angle brackets.
    public let references: [String]
    /// The body as Markdown. Empty when the message has no text or HTML part.
    public let body: String
    /// The part that `body` came from. `nil` when the message has no text or HTML part.
    public let bodySource: BodySource?
    /// Every part that is not a body part, in section order: the file
    /// attachments and the inline parts.
    public let attachments: [MessageAttachment]

    public init(
        messageID: String?,
        subject: String?,
        from: [MailAddress],
        to: [MailAddress],
        cc: [MailAddress],
        replyTo: [MailAddress],
        date: Date?,
        inReplyTo: String?,
        references: [String],
        body: String,
        bodySource: BodySource?,
        attachments: [MessageAttachment]
    ) {
        self.messageID = messageID
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.replyTo = replyTo
        self.date = date
        self.inReplyTo = inReplyTo
        self.references = references
        self.body = body
        self.bodySource = bodySource
        self.attachments = attachments
    }
}

/// One part of the message that is not the body, described without its
/// bytes: a file attachment, or an inline part that a terminal cannot show.
public struct MessageAttachment: Sendable, Equatable, Encodable {
    /// The decoded filename. `nil` when the part has none.
    public let filename: String?
    /// The MIME type in lowercase, without parameters, for example `application/pdf`.
    public let contentType: String
    /// The size after the transfer encoding (base64, quoted-printable) is removed.
    public let size: Int
    /// `false` for a file attachment. `true` for a part that is meant to be
    /// seen inside the message, such as an inline photo, an image that the
    /// HTML body shows, or the returned message in a bounce. An inline part
    /// that is not an image, such as a PDF, counts as a file attachment.
    public let inline: Bool

    public init(filename: String?, contentType: String, size: Int, inline: Bool) {
        self.filename = filename
        self.contentType = contentType
        self.size = size
        self.inline = inline
    }
}

/// The MIME part that a message body came from.
public enum BodySource: String, Sendable, Equatable, Encodable {
    case text, html
}

/// Which part the decoder shows as the body. When the chosen part is
/// missing, the decoder uses the other one.
public enum BodyPreference: String, CaseIterable, Sendable {
    /// The HTML part converted to Markdown when there is one, else the text part.
    case auto
    /// The text/plain part.
    case text
    /// The text/html part, converted to Markdown.
    case html
}
