import Foundation

/// A fallback for the `Date` header. EMLParser gives no date when the value
/// ends in a comment, as in `Sat, 24 Oct 2026 13:42:00 -0500 (CDT)`, which
/// many mail servers write.
enum HeaderDate {
    /// The top-level `Date` header of a raw message, parsed. `nil` when the
    /// header is missing or is not a date this reader knows.
    static func date(inRawMessage data: Data) -> Date? {
        headerValue(named: "date", inRawMessage: data).flatMap(parse)
    }

    /// An RFC 5322 date with or without the weekday, with or without seconds,
    /// and with a numeric zone. A trailing `(...)` comment is ignored.
    static func parse(_ value: String) -> Date? {
        let text = value.replacing(/\([^()]*\)\s*$/, with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }

    /// The unfolded value of the first top-level header called `name`
    /// (lowercase). The header block ends at the first empty line.
    private static func headerValue(named name: String, inRawMessage data: Data) -> String? {
        let lineFeed: UInt8 = 0x0A
        let carriageReturn: UInt8 = 0x0D
        // Like EMLParser, skip line breaks before the first header.
        let message = data.drop { $0 == lineFeed || $0 == carriageReturn }

        var headers: [String] = []
        var lineStart = message.startIndex
        while lineStart < message.endIndex {
            let lineEnd = message[lineStart...].firstIndex(of: lineFeed) ?? message.endIndex
            var line = message[lineStart..<lineEnd]
            if line.last == carriageReturn {
                line = line.dropLast()
            }
            if line.isEmpty {
                break
            }
            let text = String(decoding: line, as: UTF8.self)
            if let first = text.first, first == " " || first == "\t", !headers.isEmpty {
                headers[headers.count - 1] += text
            } else {
                headers.append(text)
            }
            lineStart = lineEnd < message.endIndex ? lineEnd + 1 : message.endIndex
        }

        for header in headers {
            guard let colon = header.firstIndex(of: ":") else { continue }
            if header[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == name {
                return String(header[header.index(after: colon)...])
            }
        }
        return nil
    }
}
