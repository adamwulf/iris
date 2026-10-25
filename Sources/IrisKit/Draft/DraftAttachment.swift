import Foundation
import SwiftMail

/// A file that `iris draft --attach` attaches to the draft. iris reads every
/// file before it connects, so a bad path fails before the login.
public struct DraftAttachment: Sendable, Equatable {
    /// The file's name in the draft: the last component of its path.
    public let filename: String
    /// The Content-Type: SwiftMail's MIME type for the file name's extension,
    /// in any case, else `application/octet-stream`.
    public let mimeType: String
    /// The file's bytes. SwiftMail writes them in base64.
    public let data: Data

    /// The file at `path`, whole. A relative path starts in the current
    /// directory. An empty file is attached as it is.
    ///
    /// Throws `draftAttachmentIsAFolder` for a folder, and
    /// `draftAttachmentNotRead` when there is no file at `path` or it cannot be read.
    public static func read(path: String) throws -> DraftAttachment {
        // For a folder, Foundation's reason is only "couldn't be opened".
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw IrisError.draftAttachmentIsAFolder(path: path)
        }
        do {
            // SwiftMail's init reads the file and takes the MIME type from its
            // own table (pinned types, then UTType), which it does not make
            // public. So the draft gets the type that SwiftMail would give the file.
            let attachment = try Attachment(fileURL: URL(fileURLWithPath: path))
            return DraftAttachment(filename: attachment.filename, mimeType: attachment.mimeType, data: attachment.data)
        } catch {
            throw IrisError.draftAttachmentNotRead(path: path, reason: error.localizedDescription)
        }
    }
}
