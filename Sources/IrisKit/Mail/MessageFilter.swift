import Foundation

/// The messages that `iris list` keeps. The server does the matching with
/// UID SEARCH, and a message must match every condition that is set. The
/// empty filter keeps every message, and `list` then sends no SEARCH.
public struct MessageFilter: Sendable, Equatable {
    /// Only messages without the `\Seen` flag.
    public var unread: Bool
    /// Only messages with the `\Flagged` flag (starred, in Gmail).
    public var flagged: Bool
    /// Only messages whose `From:` header has this text.
    public var from: String?
    /// Only messages whose `Subject:` header has this text.
    public var subject: String?
    /// Only messages that the server received on this day or later.
    public var since: CalendarDay?
    /// Only messages that the server received before this day.
    public var before: CalendarDay?

    public init(
        unread: Bool = false,
        flagged: Bool = false,
        from: String? = nil,
        subject: String? = nil,
        since: CalendarDay? = nil,
        before: CalendarDay? = nil
    ) {
        self.unread = unread
        self.flagged = flagged
        self.from = from
        self.subject = subject
        self.since = since
        self.before = before
    }

    /// Whether no condition is set, so every message matches.
    public var isEmpty: Bool {
        self == MessageFilter()
    }

    /// The `iris list` options that give this filter, in the order of `--help`.
    /// Text values are shell-quoted.
    var options: [String] {
        var words: [String] = []
        if unread {
            words.append("--unread")
        }
        if flagged {
            words.append("--flagged")
        }
        if let from {
            words += ["--from", MessagePage.shellQuoted(from)]
        }
        if let subject {
            words += ["--subject", MessagePage.shellQuoted(subject)]
        }
        if let since {
            words += ["--since", since.description]
        }
        if let before {
            words += ["--before", before.description]
        }
        return words
    }
}
