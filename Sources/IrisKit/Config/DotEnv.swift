import Foundation

/// Reads `KEY=value` settings from `.env` files.
///
/// The search starts in a directory (the current working directory by default)
/// and walks each parent up to the filesystem root. When two files define the
/// same key, the nearer file wins.
public enum DotEnv {

    /// Every setting from the `.env` files in `directory` and each of its parents.
    public static func loadAll(startingIn directory: URL? = nil) -> [String: String] {
        var values: [String: String] = [:]
        for fileURL in candidateFileURLs(startingIn: directory) {
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for (key, value) in parse(contents) where values[key] == nil {
                values[key] = value
            }
        }
        return values
    }

    /// The `.env` paths from `directory` up to the root, nearest first. The files may not exist.
    static func candidateFileURLs(startingIn directory: URL?) -> [URL] {
        var dir = (directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        var urls: [URL] = []
        while true {
            urls.append(dir.appendingPathComponent(".env"))
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { break }
            dir = parent
        }
        return urls
    }

    /// Parses the contents of one `.env` file, close to what `source` does with it.
    ///
    /// Rules:
    /// - Blank lines and lines that start with `#` are ignored.
    /// - A line is `KEY=value`, with an optional `export ` in front. The key has
    ///   no whitespace, so `KEY = value` is skipped.
    /// - A value in matching single or double quotes keeps everything inside
    ///   them, `#` too. The quotes are removed, and a comment may follow them.
    /// - An unquoted value ends where whitespace and then `#` start a comment.
    /// - An empty value counts as "not set".
    /// - When a file sets a key more than once, the last line wins.
    static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        // `isNewline` also matches "\r\n", which Swift treats as one Character.
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") || line.hasPrefix("export\t") {
                line = String(line.dropFirst("export".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            guard !key.isEmpty, key.rangeOfCharacter(from: .whitespaces) == nil else { continue }
            let value = parseValue(String(line[line.index(after: equals)...]))
            values[key] = value.isEmpty ? nil : value
        }
        return values
    }

    /// The value in `text`, everything after the `=`.
    private static func parseValue(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            // The value ends at the first matching quote with nothing or a comment after it.
            let inside = trimmed.dropFirst()
            var searchStart = inside.startIndex
            while let closing = inside[searchStart...].firstIndex(of: quote) {
                if isNothingOrComment(inside[inside.index(after: closing)...]) {
                    return String(inside[..<closing])
                }
                searchStart = inside.index(after: closing)
            }
        }
        guard let comment = text.range(of: "[ \t]#", options: .regularExpression) else {
            return trimmed
        }
        return text[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    private static func isNothingOrComment(_ rest: Substring) -> Bool {
        guard let first = rest.first else {
            return true
        }
        return (first == " " || first == "\t") && rest.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }
}
