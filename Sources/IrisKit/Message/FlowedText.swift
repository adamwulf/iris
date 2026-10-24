import Foundation

/// Decodes RFC 3676 `format=flowed` text: a line that ends in a space is a
/// soft break, so it is joined with the next line.
enum FlowedText {
    /// Joins the soft line breaks in `text`, which must use `\n` line endings.
    ///
    /// - Parameter deleteSpace: `true` for `delsp=yes`, where the space before
    ///   a soft break was added by the sender and is removed when lines are joined.
    ///
    /// Quoted lines keep their depth and come out as `> text`, `>> text`.
    /// Two rules are stricter than RFC 3676 so that no paragraph break is lost
    /// from a sender that does not trim its spaces: a paragraph also ends before
    /// an empty line and before the signature separator `-- `.
    static func unwrap(_ text: String, deleteSpace: Bool) -> String {
        var output: [String] = []
        // The flowed lines read so far, waiting for the line that ends them.
        var paragraph: String?
        var paragraphDepth = 0

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine[...]
            var depth = 0
            while line.first == ">" {
                depth += 1
                line = line.dropFirst()
            }
            // Space-stuffing: the sender added one space before a line that
            // starts with a space, ">" or "From ".
            if line.first == " " {
                line = line.dropFirst()
            }
            let isSignatureSeparator = line == "-- "
            let isFlowed = line.last == " " && !isSignatureSeparator

            if let open = paragraph, depth != paragraphDepth || line.isEmpty || isSignatureSeparator {
                output.append(quoted(open, depth: paragraphDepth))
                paragraph = nil
            }

            var content = String(line)
            if isFlowed && deleteSpace {
                content.removeLast()
            }
            let joined = (paragraph ?? "") + content
            if isFlowed {
                paragraph = joined
                paragraphDepth = depth
            } else {
                output.append(quoted(joined, depth: depth))
                paragraph = nil
            }
        }
        if let open = paragraph {
            output.append(quoted(open, depth: paragraphDepth))
        }
        return output.joined(separator: "\n")
    }

    private static func quoted(_ content: String, depth: Int) -> String {
        guard depth > 0 else { return content }
        let marks = String(repeating: ">", count: depth)
        return content.isEmpty ? marks : marks + " " + content
    }
}
