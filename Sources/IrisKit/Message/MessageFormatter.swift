import Foundation

/// How `iris show` prints one message.
public enum MessageOutputFormat: String, CaseIterable, Sendable {
    /// The decoded message as Markdown.
    case markdown
    /// The decoded message as JSON.
    case json
    /// The message source exactly as the server sent it (RFC 822, an `.eml` file).
    case raw
}

/// How `iris thread` prints the messages of a thread.
public enum ThreadOutputFormat: String, CaseIterable, Sendable {
    /// Each message as `iris show` prints it in Markdown, between separators.
    case markdown
    /// A JSON array of the objects that `iris show --format json` prints.
    case json
}

/// Prints a `MessageDocument` the way `iris show` does.
public enum MessageFormatter {
    /// The bytes `iris show` writes to stdout for the raw message `data`, read
    /// from `irisID`. `raw` gives the bytes unchanged, so that it stays the
    /// exact message source. The other formats decode the message, show the
    /// iris ID, and end with a newline.
    public static func render(
        rawMessage data: Data,
        irisID: IrisID,
        format: MessageOutputFormat,
        body preference: BodyPreference = .auto,
        timeZone: TimeZone = .current
    ) async throws -> Data {
        switch format {
        case .raw:
            return data
        case .markdown:
            let document = try await document(rawMessage: data, irisID: irisID, body: preference)
            return Data((markdown(document, timeZone: timeZone) + "\n").utf8)
        case .json:
            let document = try await document(rawMessage: data, irisID: irisID, body: preference)
            return Data((try json(document) + "\n").utf8)
        }
    }

    /// The line logged for a message that `render(thread:format:body:timeZone:)`
    /// leaves out: its iris ID, why, and what to run next.
    static func leftOutLine(_ id: IrisID, because failure: ThreadMessage.DownloadFailure) -> String {
        switch failure {
        case .timedOut(let seconds):
            return leftOutLine(id, because: "it did not download in \(seconds) seconds")
        case .gone:
            // `iris show` would not find it either.
            return "Left \(id) out of the thread: it is no longer in its mailbox. Run the command again."
        }
    }

    /// The line logged for a message that `render(thread:format:body:timeZone:)`
    /// leaves out for `reason`, with the command that shows its source.
    static func leftOutLine(_ id: IrisID, because reason: String) -> String {
        "Left \(id) out of the thread: \(reason). Run `iris show \(id.shellQuoted) --format raw` to see its source."
    }

    /// The raw message `data` decoded, with `irisID`, the message it was read from.
    static func document(rawMessage data: Data, irisID: IrisID, body preference: BodyPreference) async throws -> MessageDocument {
        var document = try await MessageDecoder.decode(data, body: preference)
        document.irisID = irisID
        return document
    }

    /// The line between two messages in a Markdown thread. A thematic break
    /// like the `---` lines inside each message, but written differently, so a
    /// reader of the plain text can tell the two apart.
    static let threadSeparator = "* * *"

    /// The bytes `iris thread` writes to stdout for `messages`, in their order:
    /// each message decoded, with its iris ID, as `render(rawMessage:irisID:format:body:timeZone:)`
    /// makes it. Markdown puts `threadSeparator` between the messages; JSON is
    /// one array. Both end with a newline. With no message to show, as in
    /// `OutputFormatter`, Markdown is empty and JSON is `[]`.
    ///
    /// A message that did not download, cannot be read as an email, or whose
    /// HTML cannot be converted is left out, and a `leftOutLine` is logged for
    /// it, so the rest of the thread is still shown. Every other error throws.
    public static func render(
        thread messages: [ThreadMessage],
        format: ThreadOutputFormat,
        body preference: BodyPreference = .auto,
        timeZone: TimeZone = .current
    ) async throws -> Data {
        var documents: [MessageDocument] = []
        for message in messages {
            switch message.rawMessage {
            case .failure(let failure):
                IrisLog.log(leftOutLine(message.irisID, because: failure))
            case .success(let data):
                do {
                    documents.append(try await document(rawMessage: data, irisID: message.irisID, body: preference))
                } catch IrisError.messageNotParsed(let detail) {
                    IrisLog.log(leftOutLine(message.irisID, because: "it could not be read as an email (\(detail))"))
                } catch IrisError.htmlNotConverted(let detail, _) {
                    IrisLog.log(leftOutLine(
                        message.irisID, because: "its HTML body could not be converted to Markdown (\(detail))"
                    ))
                }
            }
        }
        switch format {
        case .markdown where documents.isEmpty:
            return Data()
        case .json where documents.isEmpty:
            return Data("[]\n".utf8)
        case .markdown:
            let markdowns = documents.map { markdown($0, timeZone: timeZone) }
            return Data((markdowns.joined(separator: "\n\n\(threadSeparator)\n\n") + "\n").utf8)
        case .json:
            return Data((try OutputFormatter.json(documents, pretty: true) + "\n").utf8)
        }
    }

    /// The message as Markdown: a subject heading, the From/To/Cc/Date lines,
    /// the iris ID line when `irisID` is set, and the Apple Mail line when
    /// `appleMailURL` is set (each but the last ends in a hard break), the
    /// body, and the attachments and inline parts (only when there are any).
    /// It has no trailing newline.
    ///
    /// - Parameter timeZone: The zone for the date line. Tests pass a fixed zone.
    public static func markdown(_ document: MessageDocument, timeZone: TimeZone = .current) -> String {
        let subject = document.subject.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        var headers = [
            "**From:** \(addressList(document.from) ?? "(unknown)")",
            "**To:** \(addressList(document.to) ?? "(none)")",
        ]
        if let cc = addressList(document.cc) {
            headers.append("**Cc:** \(cc)")
        }
        let date = document.date.map { DateText.string(from: $0, timeZone: timeZone, showingZone: true) }
        headers.append("**Date:** \(date ?? "(unknown)")")
        if let irisID = document.irisID {
            // In code, so that Markdown does not read `_` or `[ ]` in the ID.
            headers.append("**Iris ID:** `\(irisID)`")
        }
        if let appleMailURL = document.appleMailURL {
            // An autolink, so that a Markdown renderer makes it clickable.
            // The URL has no space, `<`, or `>`: they are percent-encoded.
            headers.append("**Apple Mail:** <\(appleMailURL)>")
        }

        // A hard break after each header line except the last, so that a
        // Markdown renderer keeps one header per line.
        var lines = ["# \(subject ?? "(no subject)")", "", headers.joined(separator: "  \n")]
        lines += ["", "---", "", document.body.isEmpty ? "(no body)" : document.body]

        if !document.attachments.isEmpty {
            lines += ["", "---", "", "**Attachments:**"]
            lines += document.attachments.map { attachment in
                var details = [attachment.contentType, sizeText(attachment.size)]
                if attachment.inline {
                    details.append("inline")
                }
                return "- \(attachment.filename ?? "(no filename)") (\(details.joined(separator: ", ")))"
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The message as pretty JSON with sorted keys and ISO 8601 dates, for `--format json`.
    public static func json(_ document: MessageDocument) throws -> String {
        try OutputFormatter.json(document, pretty: true)
    }

    /// `Name <address>, address`, or `nil` for an empty list.
    static func addressList(_ addresses: [MailAddress]) -> String? {
        guard !addresses.isEmpty else { return nil }
        return addresses.map { address in
            address.name.map { "\($0) <\(address.address)>" } ?? address.address
        }
        .joined(separator: ", ")
    }

    /// A size in decimal units, as Finder shows it: `512 bytes`, `120 KB`, `1.5 MB`.
    static func sizeText(_ bytes: Int) -> String {
        switch bytes {
        case ..<1000:
            return bytes == 1 ? "1 byte" : "\(bytes) bytes"
        case ..<999_500:
            return "\(Int((Double(bytes) / 1000).rounded())) KB"
        case ..<999_950_000:
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        default:
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        }
    }
}
