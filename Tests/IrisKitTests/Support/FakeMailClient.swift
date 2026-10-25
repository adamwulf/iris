import Foundation
@testable import IrisKit

/// A `MailClient` and `MailWriteClient` with scripted answers. It records every
/// call, so tests can check what the reader or writer asked for and that it logged out.
actor FakeMailClient: MailWriteClient {
    enum Call: Equatable {
        case login
        case capabilities
        case listMailboxes
        case examine(String)
        case searchUIDs(MessageFilter)
        case searchHeaders(fields: [String], values: [String])
        case fetchEnvelopes(ClosedRange<Int>)
        case fetchEnvelopesByUID([UInt32])
        case fetchThreadHeaders([UInt32])
        case fetchRawMessage(UInt32)
        case select(String)
        case setSeen(Bool, UInt32)
        case logout
    }

    /// `fetchEnvelopes` stands for both envelope fetches.
    enum Method: Hashable {
        case login, capabilities, listMailboxes, examine, searchUIDs, searchHeaders, fetchEnvelopes, fetchThreadHeaders,
             fetchRawMessage, select, setSeen
    }

    /// One message in a fake mailbox, for `thread`: the headers that the header
    /// search matches and `fetchThreadHeaders` returns, and the raw message
    /// that `fetchRawMessage` returns.
    struct Message {
        var messageID: String?
        var inReplyTo: String?
        var references: [String] = []
        var subject: String?
        var date: Date?
        var internalDate: Date?

        /// The message as RFC 822 text with these headers and a one-line body.
        var raw: Data {
            var lines = ["From: Jane Doe <jane@example.com>", "To: me@example.com"]
            if let subject {
                lines.append("Subject: \(subject)")
            }
            if let date {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                lines.append("Date: \(formatter.string(from: date))")
            }
            if let messageID {
                lines.append("Message-ID: \(messageID)")
            }
            if let inReplyTo {
                lines.append("In-Reply-To: \(inReplyTo)")
            }
            if !references.isEmpty {
                lines.append("References: \(references.joined(separator: " "))")
            }
            lines += ["Content-Type: text/plain; charset=utf-8", "", "Body of \(messageID ?? "a message").", ""]
            return Data(lines.joined(separator: "\r\n").utf8)
        }

        /// The text of a header field, as the header search reads it.
        func header(_ field: String) -> String? {
            switch field.lowercased() {
            case "message-id": return messageID
            case "in-reply-to": return inReplyTo
            case "references": return references.isEmpty ? nil : references.joined(separator: " ")
            default: return nil
            }
        }

        func threadHeaders(uid: UInt32) -> ThreadHeaders {
            ThreadHeaders(
                uid: uid,
                messageID: messageID,
                inReplyTo: inReplyTo,
                references: references,
                subject: subject,
                date: date,
                internalDate: internalDate
            )
        }
    }

    private(set) var calls: [Call] = []

    private let accountName: String
    private let capabilityList: [String]
    private let mailboxList: [MailboxInfo]
    private let statuses: [String: MailboxStatus]
    private let searchResult: [UInt32]
    private let envelopes: [MessageEnvelope]
    private let rawMessages: [UInt32: Data]
    private let mailboxMessages: [String: [UInt32: Message]]
    private let errors: [Method: any Error]
    /// The wire name of the mailbox that the last EXAMINE opened.
    private var openMailbox: String?

    /// Mailbox names are wire names (modified UTF-7), as in `MailClient`:
    /// `mailboxes` holds them, `statuses` is keyed by them, and `examine` and
    /// `select` throw `unknownMailbox` with the wire name, as SwiftMailClient
    /// does, for a name that is not in `statuses`. `searchUIDs` returns `searchResult` for every
    /// filter: the server does the matching, so a test scripts its answer.
    /// `fetchEnvelopes` returns the `envelopes` whose sequence number (or UID)
    /// is asked for, in the order given. `fetchRawMessage` returns empty data
    /// for a UID that is not in `rawMessages`, as SwiftMail does. `accountName`
    /// goes in the errors the fake throws itself.
    ///
    /// `mailboxMessages` holds whole mailboxes for `thread`, by wire name and
    /// UID. A mailbox in it can be examined without a status. In such a
    /// mailbox the header search matches like a server (the text inside the
    /// field, ignoring case), `fetchThreadHeaders` returns the messages' headers,
    /// and `fetchRawMessage` returns their raw text.
    init(
        accountName: String = "work",
        capabilities: [String] = [],
        mailboxes: [MailboxInfo] = [],
        statuses: [String: MailboxStatus] = [:],
        searchResult: [UInt32] = [],
        envelopes: [MessageEnvelope] = [],
        rawMessages: [UInt32: Data] = [:],
        mailboxMessages: [String: [UInt32: Message]] = [:],
        errors: [Method: any Error] = [:]
    ) {
        self.accountName = accountName
        self.capabilityList = capabilities
        self.mailboxList = mailboxes
        self.statuses = statuses
        self.searchResult = searchResult
        self.envelopes = envelopes
        self.rawMessages = rawMessages
        self.mailboxMessages = mailboxMessages
        self.errors = errors
    }

    /// A fake whose INBOX holds `count` messages: sequence number n has UID 100 + n.
    /// SEARCH answers with `searchResult`.
    static func inbox(count: Int, searchResult: [UInt32] = []) -> FakeMailClient {
        FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: count, uidValidity: 7, uidNext: UInt32(101 + count))],
            searchResult: searchResult,
            envelopes: (0..<count).map { envelope(sequenceNumber: $0 + 1) }
        )
    }

    static func envelope(
        sequenceNumber: Int,
        seen: Bool = true,
        from: MailAddress? = MailAddress(name: "Jane Doe", address: "jane@example.com"),
        subject: String? = nil,
        date: Date? = nil,
        internalDate: Date? = nil
    ) -> MessageEnvelope {
        MessageEnvelope(
            sequenceNumber: sequenceNumber,
            uid: UInt32(100 + sequenceNumber),
            seen: seen,
            from: from,
            subject: subject ?? "Message \(sequenceNumber)",
            date: date,
            internalDate: internalDate
        )
    }

    func login() async throws {
        try record(.login, .login)
    }

    func capabilities() async throws -> [String] {
        try record(.capabilities, .capabilities)
        return capabilityList
    }

    func listMailboxes() async throws -> [MailboxInfo] {
        try record(.listMailboxes, .listMailboxes)
        return mailboxList
    }

    func examine(mailbox: String) async throws -> MailboxStatus {
        try record(.examine(mailbox), .examine)
        if let messages = mailboxMessages[mailbox] {
            openMailbox = mailbox
            return statuses[mailbox] ?? MailboxStatus(
                messageCount: messages.count, uidValidity: 7, uidNext: (messages.keys.max() ?? 0) + 1
            )
        }
        let status = try status(of: mailbox)
        openMailbox = mailbox
        return status
    }

    func searchUIDs(matching filter: MessageFilter) async throws -> [UInt32] {
        try record(.searchUIDs(filter), .searchUIDs)
        return searchResult
    }

    func searchUIDs(headers fields: [String], containingAny values: [String]) async throws -> [UInt32] {
        try record(.searchHeaders(fields: fields, values: values), .searchHeaders)
        return openMessages.filter { _, message in
            fields.contains { field in
                guard let text = message.header(field) else { return false }
                return values.contains { text.range(of: $0, options: .caseInsensitive) != nil }
            }
        }.map(\.key)
    }

    func fetchThreadHeaders(uids: [UInt32]) async throws -> [ThreadHeaders] {
        try record(.fetchThreadHeaders(uids), .fetchThreadHeaders)
        return uids.compactMap { uid in openMessages[uid]?.threadHeaders(uid: uid) }
    }

    /// The messages of the open mailbox in `mailboxMessages`.
    private var openMessages: [UInt32: Message] {
        openMailbox.flatMap { mailboxMessages[$0] } ?? [:]
    }

    func fetchEnvelopes(sequenceNumbers: ClosedRange<Int>) async throws -> [MessageEnvelope] {
        try record(.fetchEnvelopes(sequenceNumbers), .fetchEnvelopes)
        return envelopes.filter { sequenceNumbers.contains($0.sequenceNumber) }
    }

    func fetchEnvelopes(uids: [UInt32]) async throws -> [MessageEnvelope] {
        try record(.fetchEnvelopesByUID(uids), .fetchEnvelopes)
        return envelopes.filter { uids.contains($0.uid) }
    }

    func fetchRawMessage(uid: UInt32) async throws -> Data {
        try record(.fetchRawMessage(uid), .fetchRawMessage)
        if let message = openMessages[uid] {
            return message.raw
        }
        return rawMessages[uid] ?? Data()
    }

    func select(mailbox: String) async throws {
        try record(.select(mailbox), .select)
        _ = try status(of: mailbox)
    }

    func setSeen(_ seen: Bool, uid: UInt32) async throws {
        try record(.setSeen(seen, uid), .setSeen)
    }

    func logout() async {
        calls.append(.logout)
    }

    private func status(of mailbox: String) throws -> MailboxStatus {
        guard let status = statuses[mailbox] else {
            throw IrisError.unknownMailbox(account: accountName, name: mailbox, reason: "NO no such mailbox")
        }
        return status
    }

    private func record(_ call: Call, _ method: Method) throws {
        calls.append(call)
        if let error = errors[method] {
            throw error
        }
    }
}
