import Foundation

/// Tidies a body (Markdown from HTML, or plain text) for printing.
enum BodyCleanup {
    /// The most blank lines kept in a row. A longer run is cut to this length:
    /// more blank lines have no meaning in Markdown.
    static let maxBlankLines = 1

    /// Turns CRLF and lone CR line endings into `\n`.
    static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Normalizes line endings, removes trailing whitespace, cuts runs of blank
    /// lines to `maxBlankLines`, and drops blank lines at the start and end.
    ///
    /// Trailing whitespace is removed from every line, with two exceptions:
    /// - A Markdown hard break (two or more trailing spaces, as SwiftText writes
    ///   for `<br>`) is kept as exactly two spaces when the line has text and the
    ///   next line has text too. Before a blank line or at the end, a hard break
    ///   does nothing, so it is removed.
    /// - The signature separator `-- ` keeps its space.
    static func clean(_ text: String) -> String {
        let lines = normalizeLineEndings(text).split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { line in
            line == "-- " ? String(line) : String(line.reversed().drop(while: \.isWhitespace).reversed())
        }

        var result: [String] = []
        var blankRun = 0
        for (index, line) in trimmed.enumerated() {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= maxBlankLines {
                    result.append(line)
                }
                continue
            }
            blankRun = 0
            let nextHasText = index + 1 < trimmed.count && !trimmed[index + 1].isEmpty
            result.append(lines[index].hasSuffix("  ") && nextHasText ? line + "  " : line)
        }

        let start = result.firstIndex { !$0.isEmpty } ?? result.endIndex
        let end = result.lastIndex { !$0.isEmpty }.map { $0 + 1 } ?? start
        return result[start..<end].joined(separator: "\n")
    }
}
