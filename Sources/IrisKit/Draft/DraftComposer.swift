import Foundation

/// Builds a standalone draft without downloading or quoting another message.
public struct DraftComposer: Sendable {
    private let from: MailAddress
    private let to: [MailAddress]
    private let cc: [MailAddress]
    private let bcc: [MailAddress]
    private let subject: String

    /// Each recipient value is one mailbox, optionally with a display name.
    /// Headers are checked before the caller opens a mail session.
    public init(
        from: MailAddress, to: [String], cc: [String] = [], bcc: [String] = [],
        subject: String
    ) throws {
        guard !to.isEmpty else { throw IrisError.draftRecipientsMissing }
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !subject.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw IrisError.draftSubjectInvalid
        }
        self.from = from
        self.to = try Self.recipients(to, option: "--to")
        self.cc = try Self.recipients(cc, option: "--cc")
        self.bcc = try Self.recipients(bcc, option: "--bcc")
        self.subject = subject
    }

    /// Compose after validating the headers, so a typo fails before stdin is read.
    public func message(body: String, attachments: [DraftAttachment] = []) -> DraftMessage {
        let markdown = BodyCleanup.normalizeLineEndings(body)
        return DraftMessage(
            from: from, to: to, cc: cc, bcc: bcc, subject: subject,
            inReplyTo: nil, references: [], markdown: markdown,
            html: MarkdownHTML.html(fromMarkdown: markdown), attachments: attachments
        )
    }

    private static func recipients(_ values: [String], option: String) throws -> [MailAddress] {
        try values.map { value in
            guard !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
                  let address = MailAddress(parsing: value) else {
                throw IrisError.draftRecipientInvalid(option: option, value: value)
            }
            return address
        }
    }
}
