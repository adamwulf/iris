import Foundation

/// The subject rule of `iris thread`: a message is in the thread only when its
/// subject is the input message's subject, after the reply and forward prefixes
/// and the bracketed tags are removed. So a subject change starts a new thread,
/// as in Gmail, even when `References` links the new message to the old
/// conversation (Outlook users reply to an old email and change the subject).
enum ThreadSubject {
    /// `subject` without its leading `Re:`, `Fwd:`, and `Fw:` prefixes (any
    /// case) and bracketed tags such as `[list]` (Mailman writes
    /// "[list] Re: x") or `[EXTERNAL]` (corporate gateways), in any order and
    /// repeated, with each run of whitespace made one space, trimmed, and in
    /// lowercase, so that two subjects of one thread give the same text. A
    /// missing subject is the empty text.
    static func normalized(_ subject: String?) -> String {
        // A leading prefix or tag, with the whitespace around it.
        let prefix = /^\s*(?:(?:re|fwd|fw)\s*:|\[[^\]]*\])\s*/.ignoresCase()
        var text = subject ?? ""
        while let match = text.prefixMatch(of: prefix) {
            text.removeSubrange(match.range)
        }
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.joined(separator: " ").lowercased()
    }

    /// The most words that `asciiWords(_:)` gives.
    static let maxSearchWords = 5

    /// The words of `subject`, a normalized subject, that a SUBJECT search for
    /// each finds on both a word-index server (Zoho) and an RFC 3501 server,
    /// for a server that refuses the whole subject. At most `maxSearchWords`,
    /// the longest first (on a tie, the earlier one).
    ///
    /// A word is a run of letters, digits, and ASCII apostrophes; every other
    /// character, the curly apostrophe too, ends it. Only words of ASCII
    /// letters and digits that are 3 or more long are kept. Zoho's probes on
    /// 2026-10-24 showed why: it finds "bill" in "bill’s" and "single" in
    /// "single-use", but not "don" in "don't" or "you" in "you're" (a word with
    /// an ASCII apostrophe stays whole), and "ai" finds nothing (a short word).
    static func asciiWords(_ subject: String) -> [String] {
        let tokens = subject.split { !($0.isLetter || $0.isNumber || $0 == "'") }
        var words: [String] = []
        for token in tokens.map(String.init) where token.count >= 3
            && token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
            && !words.contains(token) {
            words.append(token)
        }
        let longestFirst = words.enumerated().sorted { lhs, rhs in
            lhs.element.count != rhs.element.count ? lhs.element.count > rhs.element.count : lhs.offset < rhs.offset
        }
        return longestFirst.prefix(maxSearchWords).map(\.element)
    }
}
