import Foundation

/// Builds a standalone draft without downloading or quoting another message.
public enum DraftComposer {
    /// Each recipient value is one mailbox, optionally with a display name.
    /// Headers are checked before the caller opens a mail session.
    public static func new(
        from: MailAddress, to: [String], cc: [String] = [], bcc: [String] = [],
        subject: String, body: String, attachments: [DraftAttachment] = []
    ) throws -> DraftMessage {
        guard !to.isEmpty else { throw IrisError.draftRecipientsMissing }
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !subject.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw IrisError.draftSubjectInvalid
        }
        let to = try recipients(to, option: "--to")
        let cc = try recipients(cc, option: "--cc")
        let bcc = try recipients(bcc, option: "--bcc")
        let markdown = BodyCleanup.normalizeLineEndings(body)
        return DraftMessage(
            from: from, to: to, cc: cc, bcc: bcc, subject: subject,
            inReplyTo: nil, references: [], markdown: markdown,
            html: MarkdownHTML.html(fromMarkdown: markdown), attachments: attachments
        )
    }

    private static func recipients(_ values: [String], option: String) throws -> [MailAddress] {
        try values.map { value in
            guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  let address = MailAddress(parsing: value) else {
                throw IrisError.draftRecipientInvalid(option: option)
            }
            return address
        }
    }
}
