import Foundation

/// One row of `iris list`.
public struct MessageSummary: Sendable, Equatable, Encodable {
    /// The IMAP UID. It is valid only inside the mailbox the message was listed from.
    public let uid: UInt32
    public let from: MailAddress?
    public let subject: String
    /// The `Date:` header, else the date the server received the message.
    public let date: Date?

    init(uid: UInt32, from: MailAddress?, subject: String, date: Date?) {
        self.uid = uid
        self.from = from
        self.subject = subject
        self.date = date
    }

    init(envelope: MessageEnvelope) {
        self.init(
            uid: envelope.uid,
            from: envelope.from,
            subject: envelope.subject ?? "",
            date: envelope.date ?? envelope.internalDate
        )
    }

    /// `date` as the table shows it: `yyyy-MM-dd HH:mm` in `timeZone`.
    static func tableDate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }

    /// A table cell is one line: line breaks and tabs become spaces.
    static func oneLine(_ text: String) -> String {
        String(text.map { $0.isNewline || $0 == "\t" ? " " : $0 })
    }
}

extension MessageSummary: IrisRow {
    public static var tableColumns: [String] { ["UID", "DATE", "FROM", "SUBJECT"] }

    public var tableValues: [String] {
        [
            String(uid),
            date.map { Self.tableDate($0, timeZone: .current) } ?? "",
            Self.oneLine(from?.displayName ?? ""),
            Self.oneLine(subject),
        ]
    }

    public var idValue: String { String(uid) }
}

/// One row of `iris mailboxes`.
public struct MailboxInfo: Sendable, Equatable, Encodable {
    public let name: String
    /// Special-use attributes (RFC 6154 and RFC 8457), such as `\Drafts` or `\Sent`.
    public let attributes: [String]

    public init(name: String, attributes: [String]) {
        self.name = name
        self.attributes = attributes
    }

    /// One entry per name, in the order the names first appear, with the
    /// attributes of all entries for that name, sorted and without repeats.
    static func merged(_ mailboxes: [MailboxInfo]) -> [MailboxInfo] {
        var names: [String] = []
        var attributesByName: [String: Set<String>] = [:]
        for mailbox in mailboxes {
            if attributesByName[mailbox.name] == nil {
                names.append(mailbox.name)
            }
            attributesByName[mailbox.name, default: []].formUnion(mailbox.attributes)
        }
        return names.map { MailboxInfo(name: $0, attributes: attributesByName[$0, default: []].sorted()) }
    }

    /// Name order, ignoring case. Names that differ only in case are in code-point order.
    static func areInNameOrder(_ lhs: MailboxInfo, _ rhs: MailboxInfo) -> Bool {
        switch lhs.name.caseInsensitiveCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.name < rhs.name
        }
    }
}

extension MailboxInfo: IrisRow {
    public static var tableColumns: [String] { ["NAME", "ATTRIBUTES"] }
    public var tableValues: [String] { [name, attributes.joined(separator: " ")] }
    public var idValue: String { name }
}

/// One page of `iris list`, newest message first.
public struct MessagePage: Sendable, Equatable {
    public let mailbox: String
    public let messages: [MessageSummary]
    /// The number of messages in the mailbox.
    public let totalCount: Int
    /// One-based.
    public let page: Int
    public let limit: Int
    /// Whether an older page exists.
    public let hasMore: Bool

    /// The sequence numbers on `page`, where page 1 holds the newest `limit`
    /// messages: `max(1, N - page*limit + 1) ... N - (page-1)*limit`.
    /// Nil when the page is past the end. `page` and `limit` must be 1 or more.
    static func sequenceRange(messageCount: Int, page: Int, limit: Int) -> ClosedRange<Int>? {
        let (skipped, overflow) = (page - 1).multipliedReportingOverflow(by: limit)
        guard !overflow, skipped < messageCount else {
            return nil
        }
        let newest = messageCount - skipped
        return max(1, newest - limit + 1)...newest
    }

    /// The line `iris list` writes to stderr after the table, such as
    /// `Showing 1-25 of 1234. Next page: iris list --page 2`.
    /// `account` is the `--account` value, if any, so the next-page command uses the same account.
    public func hint(account: String?) -> String {
        guard !messages.isEmpty else {
            if totalCount == 0 {
                return "\"\(mailbox)\" has no messages."
            }
            let lastPage = (totalCount - 1) / limit + 1
            return "Page \(page) is past the end: \"\(mailbox)\" has \(Self.messageCount(totalCount)), "
                + "and the last page is \(lastPage)."
        }
        let first = (page - 1) * limit + 1
        let last = first + messages.count - 1
        var line = "Showing \(first)-\(last) of \(totalCount)."
        if hasMore {
            line += " Next page: " + Self.listCommand(account: account, mailbox: mailbox, page: page + 1, limit: limit)
        }
        return line
    }

    /// The `iris list` command for these options. Options at their default values are left out.
    static func listCommand(account: String?, mailbox: String, page: Int, limit: Int) -> String {
        var words = ["iris", "list"]
        if let account {
            words += ["--account", shellQuoted(account)]
        }
        if mailbox != MailReader.defaultMailbox {
            words += ["--mailbox", shellQuoted(mailbox)]
        }
        if page != 1 {
            words += ["--page", String(page)]
        }
        if limit != MailReader.defaultPageLimit {
            words += ["--limit", String(limit)]
        }
        return words.joined(separator: " ")
    }

    /// `text` as one shell word: unchanged when it is safe, else in single quotes.
    static func shellQuoted(_ text: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./@%+=:,")
        if !text.isEmpty, text.unicodeScalars.allSatisfy(safe.contains) {
            return text
        }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// "1 message", "2 messages".
    static func messageCount(_ count: Int) -> String {
        count == 1 ? "1 message" : "\(count) messages"
    }
}

/// What `iris check` reports. It never holds the password.
public struct AccountCheck: Sendable, Equatable {
    public let account: String
    public let username: String
    public let host: String
    public let port: Int
    public let capabilities: [String]
    public let inboxMessageCount: Int

    init(account: Account, capabilities: [String], inboxMessageCount: Int) {
        self.account = account.name
        self.username = account.username
        self.host = account.host
        self.port = account.port
        self.capabilities = capabilities
        self.inboxMessageCount = inboxMessageCount
    }

    /// What `iris check` prints, one fact per line.
    public var report: String {
        [
            "Account:      \(account)",
            "Username:     \(username)",
            "Server:       \(host):\(port)",
            "Capabilities: \(capabilities.joined(separator: " "))",
            "INBOX:        \(MessagePage.messageCount(inboxMessageCount))",
        ].joined(separator: "\n")
    }
}
