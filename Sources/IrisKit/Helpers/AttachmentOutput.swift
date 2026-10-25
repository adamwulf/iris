import Foundation

/// Where `iris download` puts an attachment's bytes: on stdout, or in a new
/// file (`-o`). The CLI picks it before the download, so a terminal on
/// stdout fails before iris connects.
public enum AttachmentOutput: Sendable, Equatable {
    /// The bytes themselves on stdout, unchanged, as `iris show --format raw`
    /// writes a message.
    case stdout
    /// A new file at `path`, or, when `path` is a directory, a new file in it
    /// under the attachment's filename made safe (`safeFilename(_:attachmentID:)`).
    case file(path: String)

    /// `.file` for `-o <path>`, else `.stdout`. Without a path, a terminal on
    /// stdout throws `attachmentStdoutIsTerminal`: the bytes would garble it.
    ///
    /// - Parameter stdoutIsTerminal: Whether stdout is a terminal. The CLI checks it.
    public init(path: String?, stdoutIsTerminal: Bool) throws {
        if let path {
            self = .file(path: path)
        } else if stdoutIsTerminal {
            throw IrisError.attachmentStdoutIsTerminal
        } else {
            self = .stdout
        }
    }

    /// The bytes that `iris download` writes to stdout for `attachment`: the
    /// attachment itself for `.stdout`; for `.file`, it saves the file and
    /// gives the saved path and a newline.
    public func write(_ attachment: DownloadedAttachment) throws -> Data {
        switch self {
        case .stdout:
            return attachment.data
        case .file(let path):
            return Data((try Self.save(attachment, to: path) + "\n").utf8)
        }
    }

    /// Saves `attachment` in a new file at `path`, or in the directory `path`
    /// under its safe filename, and gives the path of the file in the form
    /// that `path` has. An existing file is never overwritten: it throws
    /// `attachmentFileExists`, and every other failure `attachmentNotSaved`.
    static func save(_ attachment: DownloadedAttachment, to path: String) throws -> String {
        var isDirectory: ObjCBool = false
        let target = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? (path as NSString).appendingPathComponent(safeFilename(attachment.filename, attachmentID: attachment.attachmentID))
            : path
        do {
            // Without overwriting, the file is created new (O_EXCL), so a file
            // or a symbolic link already at `target` stays as it is.
            try attachment.data.write(to: URL(fileURLWithPath: target), options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            throw IrisError.attachmentFileExists(path: target)
        } catch {
            throw IrisError.attachmentNotSaved(path: target, reason: error.localizedDescription)
        }
        return target
    }

    /// A file name for an attachment whose filename, from the sender, cannot
    /// be trusted: its last path component (after the last `/` or `\`),
    /// without control characters (NUL among them), and without the dots and
    /// white space at its start or the white space at its end, so it is never
    /// `.`, `..`, or a hidden file. When nothing is left, or there is no
    /// filename, `attachment-<id>`, such as `attachment-1.2`.
    static func safeFilename(_ filename: String?, attachmentID: AttachmentID) -> String {
        let fallback = "attachment-\(attachmentID)"
        guard let filename else {
            return fallback
        }
        let last = filename.split { $0 == "/" || $0 == "\\" }.last.map(String.init) ?? ""
        let printable = String(String.UnicodeScalarView(
            last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        let name = printable.drop { $0 == "." || $0.isWhitespace }.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? fallback : name
    }
}
