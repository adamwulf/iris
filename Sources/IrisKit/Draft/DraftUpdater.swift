import Foundation
import SwiftMail

/// Replaces only a draft's body. SwiftMail parses the original MIME and
/// writes the replacement; no reply composition or automatic quote runs.
enum DraftUpdater {
    static func replacingBody(in raw: Data, body: String) throws -> DraftMessage {
        let message: Message
        do {
            message = try EMLParser.parse(raw)
        } catch {
            throw IrisError.draftNotPreserved(reason: "the message could not be parsed")
        }
        let headers = MessageDecoder.headers(of: message, rawMessage: raw)
        guard headers.from.count == 1, let from = headers.from.first else {
            throw IrisError.draftNotPreserved(reason: "it must have exactly one From address")
        }
        let threading = (message.header.additionalFields ?? [:]).filter {
            $0.key == "in-reply-to" || $0.key == "references"
        }
        // SwiftMail writes additionalHeaders verbatim. Its parser unfolds
        // legitimate continuations; remaining controls cannot be emitted safely.
        for value in Array(threading.values) + [headers.messageID].compactMap({ $0 }) {
            guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\t" }) else {
                throw IrisError.draftNotPreserved(reason: "a threading header contains a control character")
            }
        }
        let attachmentIDs = Set(MessageDecoder.attachments(of: message).map(\.attachmentID))
        let attachments = try message.parts.filter {
            attachmentIDs.contains(AttachmentID(components: $0.section.components))
        }.map { part -> DraftAttachment in
            guard let data = part.decodedData() else {
                throw IrisError.draftNotPreserved(reason: "an attachment could not be decoded")
            }
            let inline = part.disposition?.lowercased() == "inline"
                || (part.disposition == nil && part.contentId != nil)
            // Email's MIME writer only emits Content-ID on inline parts.
            // Refuse this uncommon shape rather than silently lose its ID.
            guard inline || part.contentId == nil else {
                throw IrisError.draftNotPreserved(reason: "SwiftMail cannot retain a Content-ID on a non-inline attachment")
            }
            return DraftAttachment(
                filename: part.filename ?? part.suggestedFilename,
                mimeType: part.contentType, data: data,
                contentID: part.contentId, isInline: inline
            )
        }
        return DraftMessage(
            from: from, to: headers.to, cc: headers.cc,
            bcc: MessageDecoder.addresses(message.header.bccAddresses), replyTo: headers.replyTo,
            messageID: headers.messageID, subject: headers.subject ?? "",
            inReplyTo: headers.inReplyTo, references: headers.references,
            markdown: body, html: MarkdownHTML.html(fromMarkdown: body), attachments: attachments,
            preservedThreadingHeaders: threading
        )
    }
}
