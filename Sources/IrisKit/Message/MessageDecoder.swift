import Foundation
import SwiftMail
import SwiftTextHTML

/// Decodes one message into a `MessageDocument`: the raw RFC 822 bytes of
/// a whole message, or a large message that iris downloaded in parts.
/// SwiftMail's `EMLParser` does the MIME work; SwiftText turns HTML into Markdown.
public enum MessageDecoder {
    /// Decodes `data`, the full message as the server sends it for `BODY[]`.
    ///
    /// - Parameters:
    ///   - preference: Which part becomes the body. When that part is
    ///     missing, the other one is used. With `.auto`, the text part is also
    ///     used when the HTML part cannot be converted.
    ///   - full: Whether the body keeps the quoted history and signature at
    ///     its end. When false, they are left out (see `QuotedHistory`), and
    ///     `MessageDocument.bodyTrimmed` says whether any were. A forward is
    ///     never trimmed.
    public static func decode(_ data: Data, body preference: BodyPreference = .auto, full: Bool = false) async throws -> MessageDocument {
        try await decode(data, body: preference, full: full, parsingHTMLWith: htmlDocument(fromHTML:))
    }

    /// `decode(_:body:full:)` with the HTML parser as a parameter, so that
    /// tests can make it fail, and with the function that logs a note about
    /// the part shown, so that a thread can name the message in it.
    static func decode(
        _ data: Data,
        body preference: BodyPreference,
        full: Bool = false,
        parsingHTMLWith parseHTML: (String) async throws -> HTMLDocument,
        log: (String) -> Void = IrisLog.log
    ) async throws -> MessageDocument {
        let message: Message
        do {
            message = try EMLParser.parse(data)
        } catch {
            throw IrisError.messageNotParsed(reason: error.localizedDescription)
        }
        return try await document(
            of: message, headers: headers(of: message, rawMessage: data),
            preference: preference, full: full, parseHTML: parseHTML, log: log
        )
    }

    /// Decodes `parts`, a large message that iris downloaded in parts: the
    /// header fields and the parts from one FETCH, and the bytes of the body
    /// parts only. The SwiftMail message that `message(of:bodies:)` makes of
    /// them goes through the same steps as a parsed whole message, so the
    /// body and the attachment IDs are the ones a whole download gives. What
    /// differs comes from BODYSTRUCTURE (see "Large messages" in AGENTS.md):
    /// the attachment sizes can be estimates (`decodedSize(of:)`), a filename
    /// can differ, and `format=flowed` is not known, so its soft line breaks stay.
    static func decode(
        _ parts: MessageParts,
        body preference: BodyPreference,
        full: Bool = false,
        parsingHTMLWith parseHTML: (String) async throws -> HTMLDocument,
        log: (String) -> Void = IrisLog.log
    ) async throws -> MessageDocument {
        try await document(
            of: message(of: parts.outline.parts, bodies: parts.bodies), headers: parts.outline.headers,
            preference: preference, full: full, parseHTML: parseHTML, log: log
        )
    }

    /// The document of `message`, whose header fields are `headers`: what
    /// a whole message and one downloaded in parts share after the parse.
    private static func document(
        of message: Message,
        headers: MessageHeaders,
        preference: BodyPreference,
        full: Bool,
        parseHTML: (String) async throws -> HTMLDocument,
        log: (String) -> Void
    ) async throws -> MessageDocument {
        // A forward is never trimmed: the message it forwards is new to the
        // reader. The subject is in `headers`: a message downloaded in parts
        // has an empty SwiftMail header.
        let trimming = !full && !QuotedHistory.isForward(subject: headers.subject)
        let body = try await body(
            of: message, preference: preference, trimming: trimming,
            inReply: QuotedHistory.isReply(subject: headers.subject), parseHTML: parseHTML, log: log
        )
        return MessageDocument(
            messageID: headers.messageID,
            subject: headers.subject,
            from: headers.from,
            to: headers.to,
            cc: headers.cc,
            replyTo: headers.replyTo,
            date: headers.date,
            inReplyTo: headers.inReplyTo,
            references: headers.references,
            body: body.text,
            bodySource: body.source,
            bodyTrimmed: body.trimmed,
            attachments: attachments(of: message)
        )
    }

    /// The header fields of `message`, which EMLParser parsed from `data`.
    static func headers(of message: Message, rawMessage data: Data) -> MessageHeaders {
        // EMLParser leaves In-Reply-To and References in the additional fields.
        let additionalFields = message.header.additionalFields ?? [:]
        return MessageHeaders(
            messageID: message.header.messageId?.description,
            subject: message.subject,
            from: addresses(message.fromAddresses),
            to: addresses(message.toAddresses),
            cc: addresses(message.ccAddresses),
            replyTo: addresses(message.replyToAddresses),
            date: message.date ?? HeaderDate.date(inRawMessage: data),
            inReplyTo: messageIDs(in: additionalFields["in-reply-to"]).first,
            references: messageIDs(in: additionalFields["references"])
        )
    }

    /// A SwiftMail message of `parts` from BODYSTRUCTURE, with the bytes in
    /// `bodies` (by attachment ID) and no others, in the shape that EMLParser
    /// gives a whole message: without the parts inside a message/rfc822 part,
    /// which EMLParser keeps as one part and does not open. Its header is
    /// empty; the header fields are in `MessageHeaders`.
    static func message(of parts: [PartOutline], bodies: [AttachmentID: Data]) -> Message {
        let forwarded = parts.filter { mimeType(of: $0.contentType) == "message/rfc822" }.map(\.id.components)
        let own = parts.filter { part in
            !forwarded.contains { prefix in
                part.id.components.count > prefix.count && part.id.components.starts(with: prefix)
            }
        }
        return Message(header: MessageInfo(sequenceNumber: SequenceNumber(0)), parts: own.map { part in
            MessagePart(
                section: Section(part.id.components),
                contentType: part.contentType,
                disposition: part.disposition,
                encoding: part.encoding,
                filename: part.filename,
                contentId: part.contentID,
                size: part.size,
                data: bodies[part.id]
            )
        })
    }

    /// The parts of a message downloaded in parts whose bytes the decoder
    /// needs: its body parts, found by `bodyParts(of:)` as in a whole message.
    static func bodyParts(of parts: [PartOutline]) -> [PartOutline] {
        let sections = Set(bodyParts(of: message(of: parts, bodies: [:])).map(\.section))
        return parts.filter { sections.contains(Section($0.id.components)) }
    }

    /// Every part that is not a body part, in section order, so that no part
    /// of the message goes unseen. SwiftMail's `attachments` leaves out inline
    /// images (iPhone photos, images that the HTML body shows) and parts such
    /// as the returned `message/rfc822` of a bounce, so iris does not use it here.
    /// The only other parts left out are other renditions of the body, such as
    /// Gmail's AMP HTML (see `isOtherRendition(_:bodyParents:)`).
    ///
    /// Each attachment ID is the part's section. EMLParser numbers the parts
    /// as IMAP does (RFC 3501, section 6.4.5): a multipart's children are
    /// `<parent>.1`, `<parent>.2`, and so on, a body of one part is `1`, and a
    /// message/rfc822 part is one part, not opened. So each ID is a section
    /// that `BODY[<section>]` fetches, which `iris download` uses.
    static func attachments(of message: Message) -> [MessageAttachment] {
        let bodySections = Set(bodyParts(of: message).map(\.section))
        let bodyParents = Set(bodySections.map(parentSection(of:)))
        return message.parts.filter { part in
            !bodySections.contains(part.section) && !isOtherRendition(part, bodyParents: bodyParents)
        }.map { part in
            let size = decodedSize(of: part)
            return MessageAttachment(
                attachmentID: AttachmentID(components: part.section.components),
                filename: part.filename.flatMap { $0.isEmpty ? nil : $0 },
                contentType: mimeType(of: part.contentType),
                size: size.bytes,
                sizeIsEstimate: size.isEstimate,
                inline: part.disposition?.lowercased() == "inline"
            )
        }
    }

    /// The share of a base64 part's size that is data: each line of 76
    /// characters and CRLF holds 57 bytes. Senders' mail apps, and SwiftMail
    /// itself, write lines of 76; a part without line breaks holds 3/4, which
    /// is 3% more.
    static let base64DataShare = (bytes: 57, encoded: 78)

    /// The size of `part` without its Content-Transfer-Encoding. A part with
    /// bytes (every part of a whole message) gives the exact size. A part
    /// without them (an attachment of a message downloaded in parts) has only
    /// BODYSTRUCTURE's size of the encoded body. That is the exact size
    /// without an encoding (7bit, 8bit, binary), and an estimate with one:
    /// `base64DataShare` of it for base64, and all of it for quoted-printable
    /// (or an encoding iris does not know), which only gets smaller when
    /// decoded. No size is an estimate of 0.
    static func decodedSize(of part: MessagePart) -> (bytes: Int, isEstimate: Bool) {
        if let data = part.decodedData() {
            return (data.count, false)
        }
        guard let size = part.size else {
            return (0, true)
        }
        switch part.encoding?.lowercased() {
        case nil, "7bit", "8bit", "binary":
            return (size, false)
        case "base64":
            return (size * base64DataShare.bytes / base64DataShare.encoded, true)
        default:
            return (size, true)
        }
    }

    /// The content types that senders use only for another rendition of the
    /// body, next to text/plain and text/html in a multipart/alternative: Gmail's
    /// AMP HTML (Google Docs comment notifications, for example), Apple Watch
    /// HTML, and the old enriched and rich text formats.
    static let otherRenditionTypes: Set<String> = [
        "text/x-amp-html", "text/watch-html", "text/enriched", "text/richtext",
    ]

    /// Whether a part is another rendition of the body: a part of one of the
    /// `otherRenditionTypes`, with no filename and no Content-Disposition, that
    /// has a body part as a sibling (the same parent section).
    ///
    /// SwiftMail keeps only the leaf parts, not the multipart types, so a
    /// sibling can also be in a multipart/mixed or multipart/report. The type
    /// list is what keeps parts such as text/calendar and text/rfc822-headers
    /// next to the body in the list.
    ///
    /// - Parameter bodyParents: The parent section of each body part.
    static func isOtherRendition(_ part: MessagePart, bodyParents: Set<[Int]>) -> Bool {
        otherRenditionTypes.contains(mimeType(of: part.contentType))
            && (part.filename?.isEmpty ?? true)
            && part.disposition == nil
            && bodyParents.contains(parentSection(of: part.section))
    }

    /// The section numbers of the multipart that holds a part: `[1, 2]` for
    /// part 1.2.3, and `[]` for a part of the top-level multipart.
    static func parentSection(of section: Section) -> [Int] {
        Array(section.components.dropLast())
    }

    /// The body as Markdown, the part it came from, and whether quoted
    /// history or a signature was left out of it. When the message has
    /// several parts of the chosen type, the body joins all of them. A note
    /// about which part is shown goes to `log`.
    ///
    /// - Parameters:
    ///   - trimming: Whether to leave out the quoted history and signature at
    ///     the end of the body (see `QuotedHistory`).
    ///   - inReply: Whether the message is a reply (`QuotedHistory.isReply`),
    ///     from its header fields.
    static func body(
        of message: Message,
        preference: BodyPreference,
        trimming: Bool,
        inReply: Bool,
        parseHTML: (String) async throws -> HTMLDocument,
        log: (String) -> Void
    ) async throws -> (text: String, source: BodySource?, trimmed: Bool) {
        let parts = bodyParts(of: message)
        let texts = parts.filter { isPlainText($0) }.compactMap { part in
            part.textContent.map { plainText($0, contentType: part.contentType) }
        }
        // A text part that is empty or only whitespace has nothing to show
        // (some marketing tools and iPhone photo mails send one next to the
        // HTML part), so it counts as no text part, and the HTML part is used instead.
        let joinedText = joinedPieces(texts)
        let text = joinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joinedText
        // An HTML part that is empty or only whitespace has nothing to show,
        // so it counts as no HTML part, and the text part is used instead.
        let htmls = parts.filter { !isPlainText($0) }.compactMap(\.textContent).filter { html in
            !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let html = htmls.isEmpty ? nil : htmls

        if preference != .text, let html {
            do {
                let converted = try await markdown(
                    fromHTMLParts: html, hasTextPart: text != nil, trimming: trimming, inReply: inReply, parseHTML: parseHTML
                )
                return (converted.text, .html, converted.trimmed)
            } catch IrisError.htmlNotConverted(let reason, _) where preference == .auto && text != nil {
                IrisLog.record(.htmlConversionFallback)
                log("The HTML part could not be converted to Markdown (\(reason)), so the text part is shown.")
            }
        }
        if let text {
            if preference == .html && html == nil {
                IrisLog.record(.bodyFormatFallback)
                log("The message has no html part, so the text part is shown.")
            }
            // The joined text, so that only the end of the whole body is cut.
            if trimming, case .trimmed(let kept) = QuotedHistory.trim(text) {
                return (kept, .text, true)
            }
            return (text, .text, false)
        }
        guard let html else {
            return ("", nil, false)
        }
        // Only `.text` gets here with an HTML part: the other choices returned or threw above.
        IrisLog.record(.bodyFormatFallback)
        log("The message has no text part, so the html part is shown.")
        let converted = try await markdown(
            fromHTMLParts: html, hasTextPart: false, trimming: trimming, inReply: inReply, parseHTML: parseHTML
        )
        return (converted.text, .html, converted.trimmed)
    }

    /// The parts that make up the body, in section order: the text/plain and
    /// text/html parts that are not attachments. A message can have several
    /// parts of one type, because Apple Mail and iPhone Mail split the body
    /// around each inline attachment, for example
    /// `multipart/mixed(text/plain, application/pdf, text/plain)`, or, for
    /// HTML, `multipart/alternative(text/plain, multipart/mixed(text/html, image/jpeg, text/html))`.
    static func bodyParts(of message: Message) -> [MessagePart] {
        let attachmentSections = Set(message.attachments.map(\.section))
        return message.bodies.filter { !attachmentSections.contains($0.section) }
    }

    /// Whether a body part is text/plain. The other body parts are text/html.
    static func isPlainText(_ part: MessagePart) -> Bool {
        part.contentType.lowercased().hasPrefix("text/plain")
    }

    /// Each HTML part converted to Markdown, joined in order, and whether
    /// quoted history or a signature was left out.
    ///
    /// - Parameters:
    ///   - hasTextPart: Whether the message has a text part, so that the
    ///     error can say what to do next.
    ///   - trimming: Whether to leave out the quoted history and signature at
    ///     the end: first the HTML elements that mark them, then the text
    ///     markers in the Markdown (see `QuotedHistory`). When that leaves
    ///     nothing, or the Markdown has an unquoted forward marker above its
    ///     history (`QuotedHistory.TextTrim.forward`), the whole body is kept.
    ///   - inReply: Whether the message is a reply, so that a quoted forward
    ///     at its end is the forward it answers (see
    ///     `QuotedHistory.removeHistory(fromHTMLParts:inReply:)`).
    /// - Throws: `IrisError.htmlNotConverted` when a part cannot be parsed.
    static func markdown(
        fromHTMLParts htmls: [String],
        hasTextPart: Bool,
        trimming: Bool,
        inReply: Bool = false,
        parseHTML: (String) async throws -> HTMLDocument
    ) async throws -> (text: String, trimmed: Bool) {
        let documents = try await htmlDocuments(htmls, hasTextPart: hasTextPart, parseHTML: parseHTML)
        guard trimming else {
            return (markdown(of: documents), false)
        }
        let removal = QuotedHistory.removeHistory(fromHTMLParts: documents, inReply: inReply)
        let zohoHeaders = QuotedHistory.zohoHeaderBlocks(in: documents)
        let converted = markdown(of: documents)
        let trim = QuotedHistory.trim(
            converted, fromHTML: true, afterRemovedQuote: removal.quote, zohoHeaders: zohoHeaders,
            keptAnswers: removal.keptAnswers
        )
        if case .trimmed(let kept) = trim {
            return (kept, true)
        }
        if removal.any && (converted.isEmpty || trim != .noMarker) {
            // The body was all history, or it is a forward, so it is shown
            // whole. The elements are gone from these documents, so the
            // parts are parsed again.
            return (markdown(of: try await htmlDocuments(htmls, hasTextPart: hasTextPart, parseHTML: parseHTML)), false)
        }
        return (converted, removal.any)
    }

    /// Each HTML part parsed.
    ///
    /// - Throws: `IrisError.htmlNotConverted` when a part cannot be parsed.
    static func htmlDocuments(
        _ htmls: [String],
        hasTextPart: Bool,
        parseHTML: (String) async throws -> HTMLDocument
    ) async throws -> [HTMLDocument] {
        var documents: [HTMLDocument] = []
        for html in htmls {
            do {
                documents.append(try await parseHTML(html))
            } catch {
                throw IrisError.htmlNotConverted(reason: String(describing: error), hasTextPart: hasTextPart)
            }
        }
        return documents
    }

    /// The parsed HTML parts as Markdown, joined in order.
    static func markdown(of documents: [HTMLDocument]) -> String {
        joinedPieces(documents.map { BodyCleanup.clean($0.markdown()) })
    }

    /// The pieces of a body that was split into several parts, with a blank
    /// line between them. Empty pieces are left out.
    static func joinedPieces(_ pieces: [String]) -> String {
        pieces.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// A text/plain body, with `format=flowed` soft breaks joined. It is not
    /// escaped: Markdown characters in the text stay as the sender wrote them.
    static func plainText(_ text: String, contentType: String) -> String {
        let parameters = contentTypeParameters(contentType)
        var text = BodyCleanup.normalizeLineEndings(text)
        if parameters["format"]?.lowercased() == "flowed" {
            text = FlowedText.unwrap(text, deleteSpace: parameters["delsp"]?.lowercased() == "yes")
        }
        return BodyCleanup.clean(text)
    }

    /// A text/html body parsed into SwiftText's DOM. It throws SwiftText's
    /// error; `htmlDocuments(_:hasTextPart:parseHTML:)` turns it into an `IrisError`.
    static func htmlDocument(fromHTML html: String) async throws -> HTMLDocument {
        try await HTMLDocument(data: Data(declaringUTF8(html).utf8), encoding: .utf8)
    }

    /// SwiftMail has already decoded the HTML with the part's charset, so it is
    /// handed to SwiftText as UTF-8. libxml2 still obeys a charset in a `<meta>`
    /// tag over the encoding that SwiftText passes, so a stale
    /// `charset=iso-8859-1` would turn "café" into "cafÃ©". This points every
    /// `<meta>` charset at UTF-8.
    static func declaringUTF8(_ html: String) -> String {
        html.replacing(/<meta\b[^>]*>/.ignoresCase()) { tag in
            tag.output.replacing(/(charset\s*=\s*["']?)[^"'\s;\/>]+/.ignoresCase()) { charset in
                "\(charset.output.1)utf-8"
            }
        }
    }

    /// The parameters of a Content-Type value, with lowercase names and
    /// unquoted values. The first copy of a repeated name wins.
    static func contentTypeParameters(_ contentType: String) -> [String: String] {
        var segments: [String] = [""]
        var inQuotes = false
        for character in contentType {
            if character == "\"" {
                inQuotes.toggle()
            }
            if character == ";" && !inQuotes {
                segments.append("")
            } else {
                segments[segments.count - 1].append(character)
            }
        }

        var parameters: [String: String] = [:]
        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let name = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if parameters[name] == nil {
                parameters[name] = value
            }
        }
        return parameters
    }

    /// `application/pdf; charset=x` → `application/pdf`.
    static func mimeType(of contentType: String) -> String {
        let type = contentType.split(separator: ";", maxSplits: 1).first ?? ""
        return type.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Every mailbox in an address header. Groups are replaced by their
    /// members, and text that is not a valid address is kept as the address.
    static func addresses(_ entries: [AddressListEntry]) -> [MailAddress] {
        entries.flatMap { entry -> [MailAddress] in
            switch entry {
            case .mailbox(let address):
                return [MailAddress(name: address.name, address: address.address)]
            case .group(_, let members):
                return members.map { MailAddress(name: $0.name, address: $0.address) }
            case .invalid(let text):
                return [MailAddress(name: nil, address: text)]
            }
        }
    }

    /// The `<id@domain>` message IDs in a header value such as References, in order.
    static func messageIDs(in value: String?) -> [String] {
        guard let value else { return [] }
        return value.matches(of: /<[^<>]*>/).compactMap { MessageID(String($0.output))?.description }
    }
}
