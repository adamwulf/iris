import Foundation
import SwiftTextHTML

/// How `iris show` prints one message.
public enum MessageOutputFormat: String, CaseIterable, Sendable {
    /// The decoded message as Markdown.
    case markdown
    /// The decoded message as JSON.
    case json
    /// The message source exactly as the server sent it (RFC 822, an `.eml` file).
    case raw

    /// The format in which `MessageFormatter.render(message:irisID:format:body:timeZone:)`
    /// prints the decoded message, or nil for `raw`, which is the message
    /// source: `MailReader.rawMessage(_:)` downloads it whole, at any size.
    public var documentFormat: MessageDocumentFormat? {
        switch self {
        case .markdown: return .markdown
        case .json: return .json
        case .raw: return nil
        }
    }
}

/// The `MessageOutputFormat`s that decode the message, so that `iris show`
/// can download a large one in parts (`MailReader.message(_:)`).
public enum MessageDocumentFormat: CaseIterable, Sendable {
    case markdown, json
}

/// How `iris thread` prints a thread (its `--format`).
public enum ThreadOutputFormat: String, CaseIterable, Sendable {
    /// Each message as `iris show` prints it in Markdown, between separators.
    case markdown
    /// A JSON array of the objects that `iris show --format json` prints.
    case json
    /// The objects of `json`, one compact object per line, as the list commands print `jsonl`.
    case jsonl
    /// The iris ID of each message, one per line, as `iris list --format id`
    /// prints them. The walk finds them from headers alone, so `iris thread`
    /// downloads no message for it.
    case id

    /// The format in which `MessageFormatter.render(thread:format:body:full:timeZone:)`
    /// prints the downloaded messages, or nil for `id`, which needs no
    /// download: `MailReader.threadIDs(_:)` gives the iris IDs, and
    /// `MessageFormatter.render(threadIDs:)` prints them.
    public var messagesFormat: ThreadMessagesFormat? {
        switch self {
        case .markdown: return .markdown
        case .json: return .json
        case .jsonl: return .jsonl
        case .id: return nil
        }
    }
}

/// The `ThreadOutputFormat`s that show the messages themselves, so that
/// `iris thread` downloads them.
public enum ThreadMessagesFormat: CaseIterable, Sendable {
    case markdown, json, jsonl
}

/// Prints a `MessageDocument` the way `iris show` does.
public enum MessageFormatter {
    /// The bytes `iris show` writes to stdout in Markdown or JSON for
    /// `message`, read from `irisID`, as `MailReader.message(_:)` downloaded
    /// it (whole, or a large one in parts): decoded, with the iris ID shown,
    /// ending with a newline. For `--format raw`, `iris show` writes the bytes
    /// of `MailReader.rawMessage(_:)` unchanged, so they stay the exact source.
    ///
    /// - Parameter full: Whether the body keeps the quoted history and
    ///   signature at its end (`MessageDecoder.decode(_:body:full:)`).
    public static func render(
        message: DownloadedMessage,
        irisID: IrisID,
        format: MessageDocumentFormat,
        body preference: BodyPreference = .auto,
        full: Bool = false,
        timeZone: TimeZone = .current
    ) async throws -> Data {
        let document = try await document(message: message, irisID: irisID, body: preference, full: full)
        switch format {
        case .markdown:
            return Data((markdown(document, timeZone: timeZone) + "\n").utf8)
        case .json:
            return Data((try json(document) + "\n").utf8)
        }
    }

    /// The line logged for a message that `render(thread:format:body:full:timeZone:)`
    /// leaves out: its iris ID, why, and what to do next.
    static func leftOutLine(_ id: IrisID, because reason: String, then nextStep: String) -> String {
        "Left \(id) out of the thread: \(reason). \(nextStep)"
    }

    /// The `leftOutLine` for a message that did not download.
    static func leftOutLine(_ id: IrisID, because failure: ThreadMessage.DownloadFailure) -> String {
        switch failure {
        case .timedOut(let seconds):
            // `iris show` downloads it under the same limit, so it would most likely time out too.
            return leftOutLine(
                id,
                because: "it did not download in \(seconds) seconds",
                then: "It may be large, or the connection may be slow. Try again on a faster connection."
            )
        case .bodyTimedOut(let seconds):
            // `iris show` downloads the same body parts under the same limit.
            return leftOutLine(
                id,
                because: "its body did not download in \(seconds) seconds",
                then: "It may be large, or the connection may be slow. Try again on a faster connection."
            )
        case .bodyNotReceived:
            // An unsolicited FETCH came first; the next session most likely has none.
            return leftOutLine(id, because: "the server sent no bytes for its body", then: "Run the command again.")
        case .gone:
            // `iris show` would not find it either.
            return leftOutLine(id, because: "it is no longer in its mailbox", then: "Run the command again.")
        }
    }

    /// The next step for a message whose source might say what is wrong with it.
    static func showSourceStep(_ id: IrisID) -> String {
        "Run `iris show \(id.shellQuoted) --format raw` to see its source."
    }

    /// `message` decoded, whole or from its parts, with `irisID`, the message
    /// it was read from. A note about the part shown goes to `log`.
    static func document(
        message: DownloadedMessage,
        irisID: IrisID,
        body preference: BodyPreference,
        full: Bool = false,
        parsingHTMLWith parseHTML: (String) async throws -> HTMLDocument = MessageDecoder.htmlDocument(fromHTML:),
        log: (String) -> Void = IrisLog.log
    ) async throws -> MessageDocument {
        var document: MessageDocument
        switch message {
        case .whole(let data):
            document = try await MessageDecoder.decode(data, body: preference, full: full, parsingHTMLWith: parseHTML, log: log)
        case .parts(let parts):
            document = try await MessageDecoder.decode(parts, body: preference, full: full, parsingHTMLWith: parseHTML, log: log)
        }
        document.irisID = irisID
        return document
    }

    /// The line between two messages in a Markdown thread. A thematic break
    /// like the `---` lines inside each message, but written differently, so a
    /// reader of the plain text can tell the two apart.
    static let threadSeparator = "* * *"

    /// The bytes `iris thread --format id` writes to stdout for `ids`: one
    /// iris ID per line, each line ending with a newline, as `iris list --format id`
    /// writes them.
    public static func render(threadIDs ids: [IrisID]) -> Data {
        Data(ids.map { "\($0)\n" }.joined().utf8)
    }

    /// The bytes `iris thread` writes to stdout for `messages`, in their order:
    /// each message decoded, with its iris ID, as `render(message:irisID:format:body:full:timeZone:)`
    /// makes it. Markdown puts `threadSeparator` between the messages; JSON is
    /// one array; JSON Lines is one compact object per line. Each ends with a
    /// newline. A note about the part shown of a message is logged with the
    /// message's iris ID.
    ///
    /// A message that did not download, cannot be read as an email, or whose
    /// HTML cannot be converted is left out, and a `leftOutLine` is logged for
    /// it, so the rest of the thread is still shown. When no message is left
    /// to show, the error of the input message (`ThreadMessage.isInput`) is
    /// thrown, as `iris show` would throw it. Every other error throws.
    ///
    /// - Parameter full: Whether each body keeps the quoted history and
    ///   signature at its end. Without it, each message shows only its own text.
    public static func render(
        thread messages: [ThreadMessage],
        format: ThreadMessagesFormat,
        body preference: BodyPreference = .auto,
        full: Bool = false,
        timeZone: TimeZone = .current
    ) async throws -> Data {
        try await render(
            thread: messages, format: format, body: preference, full: full, timeZone: timeZone,
            parsingHTMLWith: MessageDecoder.htmlDocument(fromHTML:)
        )
    }

    /// `render(thread:format:body:full:timeZone:)` with the HTML parser as a parameter, so that tests can make it fail.
    static func render(
        thread messages: [ThreadMessage],
        format: ThreadMessagesFormat,
        body preference: BodyPreference,
        full: Bool = false,
        timeZone: TimeZone,
        parsingHTMLWith parseHTML: (String) async throws -> HTMLDocument
    ) async throws -> Data {
        var documents: [MessageDocument] = []
        var leftOut: [(message: ThreadMessage, error: IrisError, line: String)] = []
        for message in messages {
            let id = message.irisID
            switch message.download {
            case .failure(let failure):
                leftOut.append((message, failure.irisError(for: id), leftOutLine(id, because: failure)))
            case .success(let downloaded):
                do {
                    documents.append(try await document(
                        message: downloaded, irisID: id, body: preference, full: full, parsingHTMLWith: parseHTML
                    ) { note in
                        IrisLog.log("\(id): \(note)")
                    })
                } catch IrisError.messageNotParsed(let detail) {
                    let line = leftOutLine(id, because: "it could not be read as an email (\(detail))", then: showSourceStep(id))
                    leftOut.append((message, .messageNotParsed(reason: detail), line))
                } catch IrisError.htmlNotConverted(let detail, let hasTextPart) {
                    // A text part is there only with --body html: the other choices show it instead.
                    let line = leftOutLine(
                        id,
                        because: "its HTML body could not be converted to Markdown (\(detail))",
                        then: hasTextPart ? "Run `iris show \(id.shellQuoted) --body text` to see its text part." : showSourceStep(id)
                    )
                    leftOut.append((message, .htmlNotConverted(reason: detail, hasTextPart: hasTextPart), line))
                }
            }
        }
        if documents.isEmpty, let failed = leftOut.first(where: \.message.isInput) {
            for other in leftOut where other.message.irisID != failed.message.irisID {
                IrisLog.log(other.line, fileEvent: .threadMessageOmitted)
            }
            throw failed.error
        }
        for item in leftOut {
            IrisLog.log(item.line, fileEvent: .threadMessageOmitted)
        }
        switch format {
        case .markdown:
            let markdowns = documents.map { markdown($0, timeZone: timeZone) }
            return Data((markdowns.joined(separator: "\n\n\(threadSeparator)\n\n") + "\n").utf8)
        case .json:
            return Data((try OutputFormatter.json(documents, pretty: true) + "\n").utf8)
        case .jsonl:
            return Data(try documents.map { try OutputFormatter.json($0, pretty: false) + "\n" }.joined().utf8)
        }
    }

    /// The line under a body whose end was left out (`MessageDocument.bodyTrimmed`).
    static let trimmedNote = "(Quoted text or signature hidden: --full shows it.)"

    /// The message as Markdown: a subject heading, the From/To/Cc/Date lines,
    /// the iris ID line when `irisID` is set, and the Apple Mail line when
    /// `appleMailURL` is set (each but the last ends in a hard break), the
    /// body, `trimmedNote` when the end of the body was left out, and the
    /// attachments and inline parts (only when there are any), each with its
    /// attachment ID first. It has no trailing newline.
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
        if document.bodyTrimmed {
            lines += ["", trimmedNote]
        }

        if !document.attachments.isEmpty {
            lines += ["", "---", "", "**Attachments:**"]
            lines += document.attachments.map { attachment in
                let size = sizeText(attachment.size)
                var details = [attachment.contentType, attachment.sizeIsEstimate ? "about \(size)" : size]
                if attachment.inline {
                    details.append("inline")
                }
                // The attachment ID first, in code like the iris ID, so it is easy to copy.
                return "- `\(attachment.attachmentID)` \(attachment.filename ?? "(no filename)") "
                    + "(\(details.joined(separator: ", ")))"
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
