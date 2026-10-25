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
        case searchSubject([String])
        case searchMessageIDs([String])
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
        case login, capabilities, listMailboxes, examine, searchUIDs, searchSubject, searchMessageIDs, fetchEnvelopes,
             fetchThreadHeaders, fetchRawMessage, select, setSeen
    }

    /// How the fake answers a search in a mailbox of `mailboxMessages`.
    enum SearchRules: CaseIterable {
        /// As Zoho answered the probes on 2026-10-24 (see `zohoHeaderMatch`
        /// and `zohoSubjectMatches`).
        case zoho
        /// As RFC 3501 says: the text inside the header or the subject, ignoring case.
        case rfc3501
    }

    /// One message in a fake mailbox, for `thread`: the headers that the
    /// searches match and `fetchThreadHeaders` returns, and the raw message
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
    private let searchRules: SearchRules
    private let refusesNonASCII: Bool
    private let rawMessageErrors: [UInt32: any Error]
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
    /// mailbox the SUBJECT and Message-ID searches answer by `searchRules`,
    /// `fetchThreadHeaders` returns the messages' headers, and
    /// `fetchRawMessage` returns their raw text. With `refusesNonASCII`, the
    /// SUBJECT search refuses text that is not ASCII, as a server without
    /// UTF-8 SEARCH does (NO [BADCHARSET]); Zoho accepted it in the probes.
    /// `fetchRawMessage` throws the error in `rawMessageErrors` for its UID.
    init(
        accountName: String = "work",
        capabilities: [String] = [],
        mailboxes: [MailboxInfo] = [],
        statuses: [String: MailboxStatus] = [:],
        searchResult: [UInt32] = [],
        envelopes: [MessageEnvelope] = [],
        rawMessages: [UInt32: Data] = [:],
        mailboxMessages: [String: [UInt32: Message]] = [:],
        searchRules: SearchRules = .zoho,
        refusesNonASCII: Bool = false,
        rawMessageErrors: [UInt32: any Error] = [:],
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
        self.searchRules = searchRules
        self.refusesNonASCII = refusesNonASCII
        self.rawMessageErrors = rawMessageErrors
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

    func searchUIDs(subjectContainingAll texts: [String]) async throws -> [UInt32] {
        try record(.searchSubject(texts), .searchSubject)
        if refusesNonASCII && !texts.allSatisfy({ $0.unicodeScalars.allSatisfy(\.isASCII) }) {
            // What SwiftMailClient makes of NO [BADCHARSET].
            throw IrisError.searchFailed(account: accountName, reason: "NO [BADCHARSET (US-ASCII)] Unsupported charset")
        }
        return openMessages.filter { _, message in
            texts.allSatisfy { text in
                switch searchRules {
                case .zoho: return Self.zohoSubjectMatches(message.subject, text)
                case .rfc3501: return Self.contains(message.subject, text)
                }
            }
        }.map(\.key)
    }

    func searchUIDs(messageIDs: [String]) async throws -> [UInt32] {
        try record(.searchMessageIDs(messageIDs), .searchMessageIDs)
        return openMessages.filter { _, message in
            messageIDs.contains { id in
                switch searchRules {
                case .zoho: return Self.zohoMessageIDMatches(message.messageID, id)
                case .rfc3501: return Self.contains(message.messageID, id)
                }
            }
        }.map(\.key)
    }

    /// Whether `text` has `value` in it, ignoring case, as RFC 3501 says SEARCH matches.
    private static func contains(_ text: String?, _ value: String) -> Bool {
        text?.range(of: value, options: .caseInsensitive) != nil
    }

    // The search rules below come from the probes against Zoho
    // (imappro.zoho.com) on 2026-10-24. RFC 3501 asks for a substring match
    // in any header, but Zoho searches a word index.

    /// Zoho's HEADER Message-ID search: the whole ID, with or without the angle
    /// brackets, ignoring case. (HEADER In-Reply-To and References never
    /// matched, so iris does not send them.)
    private static func zohoMessageIDMatches(_ messageID: String?, _ value: String) -> Bool {
        guard let messageID else {
            return false
        }
        func bare(_ id: String) -> String {
            id.trimmingCharacters(in: CharacterSet(charactersIn: "<>")).lowercased()
        }
        return bare(messageID) == bare(value)
    }

    /// Zoho's SUBJECT key: each word of `text` that is 3 or more long must be
    /// a whole word of the subject, ignoring case ("Champ" does not find
    /// "Champion"), and a key with no such word finds nothing ("ai" found
    /// nothing; "introduction for ai application work" found the thread). A
    /// word ends at any character but a letter, digit, or ASCII apostrophe:
    /// "bill" finds "bill’s" and "single" finds "single-use", but "don" does
    /// not find "don't", nor "you" find "you're". A word that ends in "'s"
    /// is also found without it ("vanguard" finds "Vanguard's"). Text that is
    /// not ASCII is accepted.
    private static func zohoSubjectMatches(_ subject: String?, _ text: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
        }
        var index = Set(words(subject ?? ""))
        for word in index where word.hasSuffix("'s") {
            index.insert(String(word.dropLast(2)))
        }
        let wanted = words(text).filter { $0.count >= 3 }
        return !wanted.isEmpty && wanted.allSatisfy(index.contains)
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
        if let error = rawMessageErrors[uid] {
            throw error
        }
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
