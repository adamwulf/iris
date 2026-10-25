import Foundation

/// Reads the Markdown body of `iris draft reply` or `iris draft update` from
/// its one source: the argument, a file (`-F <path>`), or stdin (`-F -`, or no
/// argument and no `-F` while stdin is not a terminal).
public enum DraftBody {
    /// The `-F` value that reads stdin, as in `git commit -F -`.
    public static let stdinPath = "-"

    /// The draft body from `argument`, else from the file at `path` (stdin for `-`),
    /// else from stdin when it is not a terminal. Throws when both `argument`
    /// and `path` are given, when there is no source, and when the body cannot
    /// be read, is not UTF-8, or is empty or only whitespace.
    ///
    /// - Parameters:
    ///   - attaching: Whether the draft attaches files (`--attach`). Then an
    ///     `argument` that names a file or folder that exists is an error, also
    ///     next to `-F`: each `--attach` takes one path, so `--attach a.pdf b.pdf`
    ///     (or a pattern that matched two files) makes `b.pdf` the argument.
    ///   - stdinIsTerminal: Whether stdin is a terminal. Without an argument or
    ///     `-F`, a terminal is an error, so iris never waits silently for typing.
    ///     `-F -` reads a terminal too, after a log line that says how to end the text.
    ///   - readStdin: Reads all of stdin. Tests pass a stub.
    ///   - readFile: Reads the file at a path. Tests pass a stub.
    ///   - fileExists: Whether a file or folder is at a path. Tests pass a stub.
    public static func read(
        argument: String?,
        file path: String?,
        attaching: Bool,
        stdinIsTerminal: Bool,
        readStdin: () throws -> Data = { try FileHandle.standardInput.readToEnd() ?? Data() },
        readFile: (String) throws -> Data = { try Data(contentsOf: URL(fileURLWithPath: $0)) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> String {
        // Before draftBodyGivenTwice: with -F, a second --attach path is the
        // argument too, and "given twice" would not say why.
        if attaching, let argument, fileExists(argument) {
            throw IrisError.draftBodyNamesAFile(path: argument)
        }
        switch (argument, path) {
        case (_?, _?):
            throw IrisError.draftBodyGivenTwice
        case (let argument?, nil):
            return try nonEmpty(argument, source: "the argument")
        case (nil, let path?) where path == stdinPath:
            if stdinIsTerminal {
                IrisLog.log("Reading the draft body from stdin; end it with Ctrl-D.")
            }
            return try text(of: readStdin, source: "stdin")
        case (nil, let path?):
            return try text(of: { try readFile(path) }, source: "the file \"\(path)\"")
        case (nil, nil):
            guard !stdinIsTerminal else {
                throw IrisError.draftBodyMissing
            }
            return try text(of: readStdin, source: "stdin")
        }
    }

    /// The UTF-8 text that `read` gives, checked by `nonEmpty(_:source:)`.
    private static func text(of read: () throws -> Data, source: String) throws -> String {
        let data: Data
        do {
            data = try read()
        } catch {
            throw IrisError.draftBodyNotRead(source: source, reason: error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw IrisError.draftBodyNotUTF8(source: source)
        }
        return try nonEmpty(text, source: source)
    }

    private static func nonEmpty(_ text: String, source: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IrisError.draftBodyEmpty(source: source)
        }
        return text
    }
}
