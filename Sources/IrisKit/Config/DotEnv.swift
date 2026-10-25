import Foundation

/// Reads `KEY=value` settings from `.env` files, and writes one setting for
/// `iris auth login`.
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
            guard let line = assignment(in: rawLine) else { continue }
            let value = parseValue(line.text)
            values[line.key] = value.isEmpty ? nil : value
        }
        return values
    }

    /// The key of one line and the text after its `=`, by the rules of
    /// `parse`. Nil for a blank line, a comment, or a line that is not `KEY=value`.
    private static func assignment<S: StringProtocol>(in rawLine: S) -> (key: String, text: String)? {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { return nil }
        if line.hasPrefix("export ") || line.hasPrefix("export\t") {
            line = String(line.dropFirst("export".count)).trimmingCharacters(in: .whitespaces)
        }
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = String(line[..<equals])
        guard !key.isEmpty, key.rangeOfCharacter(from: .whitespaces) == nil else { return nil }
        return (key, String(line[line.index(after: equals)...]))
    }

    /// The nearest `.env` file, from `directory` (the current working
    /// directory by default) up to the root, that sets `key`: the file whose
    /// value `loadAll` uses. A line with an empty value does not count, as in
    /// `loadAll`. Nil when no file sets the key.
    public static func fileURL(settingKey key: String, startingIn directory: URL? = nil) -> URL? {
        candidateFileURLs(startingIn: directory).first { fileURL in
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
            return parse(contents)[key] != nil
        }
    }

    /// Sets `key` to `value` in the existing `.env` file at `fileURL`. The
    /// first line that sets `key` gets the new value, and later lines that set
    /// it are removed, so the file sets it once. When no line sets it, the new
    /// line goes at the end. Every other line, comments too, stays as it is,
    /// and the file keeps its permissions. A symbolic link stays a link: the
    /// file it points to is written. `value` is written without quotes, so it
    /// must have no whitespace, `#`, or quotes (a refresh token has none).
    public static func setValue(_ value: String, forKey key: String, in fileURL: URL) throws {
        let target = fileURL.resolvingSymlinksInPath()
        let contents = try String(contentsOf: target, encoding: .utf8)
        let permissions = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions]

        var lines = contents.components(separatedBy: "\n")
        // A final newline leaves an empty last element; the output adds it back.
        if lines.last == "" {
            lines.removeLast()
        }
        let newLine = "\(key)=\(value)"
        var replaced = false
        var output: [String] = []
        for line in lines {
            guard assignment(in: line)?.key == key else {
                output.append(line)
                continue
            }
            if !replaced {
                output.append(newLine)
                replaced = true
            }
        }
        if !replaced {
            output.append(newLine)
        }

        // An atomic write replaces the file, which resets its permissions; set them back.
        try (output.joined(separator: "\n") + "\n").write(to: target, atomically: true, encoding: .utf8)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
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
