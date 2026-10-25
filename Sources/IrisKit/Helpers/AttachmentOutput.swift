import Foundation

/// Where `iris download` puts an attachment's bytes: on stdout, or in a new
/// file (`-o`). The CLI picks it before the download, so a bad choice fails
/// before iris connects. iris never makes a file name from the sender's text:
/// `-o` is the whole path of the file.
public enum AttachmentOutput: Sendable, Equatable {
    /// The bytes themselves on stdout, unchanged, as `iris show --format raw`
    /// writes a message.
    case stdout
    /// A new file at exactly this path.
    case file(path: String)

    /// `.file` for `-o <path>`, else `.stdout`. A path that is an existing
    /// folder throws `attachmentOutputIsFolder`: `-o` takes the file's path.
    /// Without a path, a terminal on stdout throws `attachmentStdoutIsTerminal`:
    /// the bytes would garble it.
    ///
    /// - Parameter stdoutIsTerminal: Whether stdout is a terminal. The CLI checks it.
    public init(path: String?, stdoutIsTerminal: Bool) throws {
        if let path {
            var isDirectory: ObjCBool = false
            guard !(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue) else {
                throw IrisError.attachmentOutputIsFolder(path: path)
            }
            self = .file(path: path)
        } else if stdoutIsTerminal {
            throw IrisError.attachmentStdoutIsTerminal
        } else {
            self = .stdout
        }
    }

    /// The bytes that `iris download` writes to stdout for `attachment`, the
    /// decoded bytes of the part: `attachment` itself for `.stdout`. For
    /// `.file`, it saves the file and gives nothing, as `iris read` prints
    /// nothing: the caller knows the path.
    ///
    /// An existing file (or folder, or symbolic link) at the path is never
    /// overwritten: it throws `attachmentFileExists`, and every other failure
    /// `attachmentNotSaved`.
    public func write(_ attachment: Data) throws -> Data {
        switch self {
        case .stdout:
            return attachment
        case .file(let path):
            do {
                // Without overwriting, the file is created new (O_EXCL), so
                // whatever is already at `path` stays as it is.
                try attachment.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
            } catch CocoaError.fileWriteFileExists {
                throw IrisError.attachmentFileExists(path: path)
            } catch {
                throw IrisError.attachmentNotSaved(path: path, reason: error.localizedDescription)
            }
            return Data()
        }
    }
}
