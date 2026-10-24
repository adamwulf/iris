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

/// Prints a `MessageDocument` the way `iris show` does.
public enum MessageFormatter {
    /// The bytes `iris show` writes to stdout for the raw message `data`.
    /// `raw` gives the bytes unchanged; the other formats decode the message
    /// and end with a newline.
    public static func render(
        rawMessage data: Data,
        format: MessageOutputFormat,
        body preference: BodyPreference = .auto,
        timeZone: TimeZone = .current
    ) async throws -> Data {
        switch format {
        case .raw:
            return data
        case .markdown:
            let document = try await MessageDecoder.decode(data, body: preference)
            return Data((markdown(document, timeZone: timeZone) + "\n").utf8)
        case .json:
            let document = try await MessageDecoder.decode(data, body: preference)
            return Data((try json(document) + "\n").utf8)
        }
    }

    /// The message as Markdown: a subject heading, the From/To/Cc/Date lines
    /// (each but the last ends in a hard break), the body, and the attachments
    /// (only when there are any). It has no trailing newline.
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
        headers.append("**Date:** \(document.date.map { dateText($0, timeZone: timeZone) } ?? "(unknown)")")

        // A hard break after each header line except the last, so that a
        // Markdown renderer keeps one header per line.
        var lines = ["# \(subject ?? "(no subject)")", "", headers.joined(separator: "  \n")]
        lines += ["", "---", "", document.body.isEmpty ? "(no body)" : document.body]

        if !document.attachments.isEmpty {
            lines += ["", "---", "", "**Attachments:**"]
            lines += document.attachments.map { attachment in
                "- \(attachment.filename ?? "(no filename)") (\(attachment.contentType), \(sizeText(attachment.size)))"
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

    /// `2026-10-24 13:42 CDT`.
    static func dateText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return formatter.string(from: date)
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
