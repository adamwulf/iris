import Foundation

/// The subject rule of `iris thread`: a message is in the thread only when its
/// subject is the input message's subject, after the reply and forward prefixes
/// are removed. So a subject change starts a new thread, as in Gmail, even when
/// `References` links the new message to the old conversation (Outlook users
/// reply to an old email and change the subject).
enum ThreadSubject {
    /// `subject` without its leading `Re:`, `Fwd:`, and `Fw:` prefixes (any
    /// case, repeated), with each run of whitespace made one space, trimmed,
    /// and in lowercase, so that two subjects of one thread give the same text.
    /// A missing subject is the empty text.
    static func normalized(_ subject: String?) -> String {
        // A leading prefix, with the whitespace around it.
        let prefix = /^\s*(?:re|fwd|fw)\s*:\s*/.ignoresCase()
        var text = subject ?? ""
        while let match = text.prefixMatch(of: prefix) {
            text.removeSubrange(match.range)
        }
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.joined(separator: " ").lowercased()
    }
}
