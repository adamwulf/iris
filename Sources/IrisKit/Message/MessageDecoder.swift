import Foundation
import SwiftMail
import SwiftTextHTML

/// Decodes the raw RFC 822 bytes of one message into a `MessageDocument`.
/// SwiftMail's `EMLParser` does the MIME work; SwiftText turns HTML into Markdown.
public enum MessageDecoder {
    /// Decodes `data`, the full message as the server sends it for `BODY[]`.
    ///
    /// - Parameter preference: Which part becomes the body. When that part is
    ///   missing, the other one is used. With `.auto`, the text part is also
    ///   used when the HTML part cannot be converted.
    public static func decode(_ data: Data, body preference: BodyPreference = .auto) async throws -> MessageDocument {
        try await decode(data, body: preference, convertingHTMLWith: markdown(fromHTML:))
    }

    /// `decode(_:body:)` with the HTML converter as a parameter, so that tests can make it fail.
    static func decode(
        _ data: Data,
        body preference: BodyPreference,
        convertingHTMLWith htmlToMarkdown: (String) async throws -> String
    ) async throws -> MessageDocument {
        let message: Message
        do {
            message = try EMLParser.parse(data)
        } catch {
            throw IrisError.messageNotParsed(reason: error.localizedDescription)
        }

        let (body, bodySource) = try await body(of: message, preference: preference, htmlToMarkdown: htmlToMarkdown)
        // EMLParser leaves In-Reply-To and References in the additional fields.
        let additionalFields = message.header.additionalFields ?? [:]
        return MessageDocument(
            messageID: message.header.messageId?.description,
            subject: message.subject,
            from: addresses(message.fromAddresses),
            to: addresses(message.toAddresses),
            cc: addresses(message.ccAddresses),
            replyTo: addresses(message.replyToAddresses),
            date: message.date ?? HeaderDate.date(inRawMessage: data),
            inReplyTo: messageIDs(in: additionalFields["in-reply-to"]).first,
            references: messageIDs(in: additionalFields["references"]),
            body: body,
            bodySource: bodySource,
            attachments: message.attachments.map { part in
                MessageAttachment(
                    filename: part.filename.flatMap { $0.isEmpty ? nil : $0 },
                    contentType: mimeType(of: part.contentType),
                    size: part.decodedData()?.count ?? 0
                )
            }
        )
    }

    /// The body as Markdown, and the part it came from.
    static func body(
        of message: Message,
        preference: BodyPreference,
        htmlToMarkdown: (String) async throws -> String
    ) async throws -> (String, BodySource?) {
        let textPart = message.findTextBodyPart()
        let text = textPart.flatMap { part in part.textContent.map { plainText($0, contentType: part.contentType) } }
        let html = message.findHtmlBodyPart()?.textContent

        if preference != .text, let html {
            do {
                return (try await htmlToMarkdown(html), .html)
            } catch IrisError.htmlNotConverted(let reason) where preference == .auto && text != nil {
                IrisLog.log("The HTML part could not be converted to Markdown (\(reason)), so the text part is shown.")
            }
        }
        if let text {
            if preference == .html && html == nil {
                IrisLog.log("The message has no html part, so the text part is shown.")
            }
            return (text, .text)
        }
        guard let html else {
            return ("", nil)
        }
        // Only `.text` gets here with an HTML part: the other choices returned or threw above.
        IrisLog.log("The message has no text part, so the html part is shown.")
        return (try await htmlToMarkdown(html), .html)
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

    /// A text/html body converted to Markdown.
    static func markdown(fromHTML html: String) async throws -> String {
        do {
            let document = try await HTMLDocument(data: Data(declaringUTF8(html).utf8), encoding: .utf8)
            return BodyCleanup.clean(document.markdown())
        } catch {
            throw IrisError.htmlNotConverted(reason: String(describing: error))
        }
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
    /// members, and text that is not a valid address is kept as the email.
    static func addresses(_ entries: [AddressListEntry]) -> [MessageAddress] {
        entries.flatMap { entry -> [MessageAddress] in
            switch entry {
            case .mailbox(let address):
                return [MessageAddress(name: address.name, email: address.address)]
            case .group(_, let members):
                return members.map { MessageAddress(name: $0.name, email: $0.address) }
            case .invalid(let text):
                return [MessageAddress(name: nil, email: text)]
            }
        }
    }

    /// The `<id@domain>` message IDs in a header value such as References, in order.
    static func messageIDs(in value: String?) -> [String] {
        guard let value else { return [] }
        return value.matches(of: /<[^<>]*>/).compactMap { MessageID(String($0.output))?.description }
    }
}
