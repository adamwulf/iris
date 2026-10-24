import Foundation

/// One decoded email, ready for `iris show`: the headers people read, the body
/// as Markdown, and a list of the attachments. It never holds attachment bytes.
public struct MessageDocument: Sendable, Equatable, Encodable {
    /// The `Message-ID` with angle brackets, for example `<abc@example.com>`.
    public let messageID: String?
    public let subject: String?
    public let from: [MessageAddress]
    public let to: [MessageAddress]
    public let cc: [MessageAddress]
    public let replyTo: [MessageAddress]
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
    public let attachments: [MessageAttachment]

    public init(
        messageID: String?,
        subject: String?,
        from: [MessageAddress],
        to: [MessageAddress],
        cc: [MessageAddress],
        replyTo: [MessageAddress],
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

/// One mailbox from an address header.
public struct MessageAddress: Sendable, Equatable, Encodable {
    /// The display name, already decoded from RFC 2047. `nil` when the header has none.
    public let name: String?
    /// The address. When the header text is not a valid address (for example
    /// `MAILER-DAEMON`), this is that text, so that nothing the sender wrote is lost.
    public let email: String

    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }
}

/// One attachment, described without its bytes.
public struct MessageAttachment: Sendable, Equatable, Encodable {
    /// The decoded filename. `nil` when the part has none.
    public let filename: String?
    /// The MIME type in lowercase, without parameters, for example `application/pdf`.
    public let contentType: String
    /// The size after the transfer encoding (base64, quoted-printable) is removed.
    public let size: Int

    public init(filename: String?, contentType: String, size: Int) {
        self.filename = filename
        self.contentType = contentType
        self.size = size
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
