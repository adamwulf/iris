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

    /// Parses the contents of one `.env` file.
    ///
    /// Rules: blank lines and `#` lines are ignored; a line must be `KEY=value`
    /// with no whitespace in the key (so `export KEY=` and `KEY = value` are
    /// skipped); one pair of matching single or double quotes is removed; an
    /// empty value counts as "not set". If a file sets a key twice, the first
    /// non-empty value wins.
    static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        // `isNewline` also matches "\r\n", which Swift treats as one Character.
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            guard !key.isEmpty, key.rangeOfCharacter(from: .whitespaces) == nil else { continue }
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first,
               first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty, values[key] == nil {
                values[key] = value
            }
        }
        return values
    }
}
