import Foundation

/// Reads mail from one account. Each call is one IMAP session: it logs in,
/// does its work, and logs out, also when the work throws.
public struct MailReader: Sendable {
    public static let defaultMailbox = "INBOX"
    public static let defaultPageLimit = 25

    public let account: Account
    private let makeClient: @Sendable (Account) -> any MailClient

    /// A reader that talks to the account's server through SwiftMail.
    public init(account: Account) {
        self.init(account: account, makeClient: { SwiftMailClient(account: $0) })
    }

    /// A reader that gets its client from `makeClient`, once per call. Tests pass a fake.
    init(account: Account, makeClient: @escaping @Sendable (Account) -> any MailClient) {
        self.account = account
        self.makeClient = makeClient
    }

    /// Logs in and reports the server's capabilities and the INBOX message count.
    public func check() async throws -> AccountCheck {
        try await withClient { client in
            let capabilities = try await client.capabilities()
            let inbox = try await examine(Self.defaultMailbox, with: client)
            return AccountCheck(account: account, capabilities: capabilities, inboxMessageCount: inbox.messageCount)
        }
    }

    /// Every mailbox with its special-use attributes, sorted by name. The names
    /// are decoded from modified UTF-7, so they are what `--mailbox` takes.
    public func mailboxes() async throws -> [MailboxInfo] {
        let listed = try await withClient { client in
            try await client.listMailboxes()
        }
        return Self.decoded(listed).sorted(by: MailboxInfo.areInNameOrder)
    }

    /// `listed`, as `listMailboxes` gives it, with decoded names, merged by
    /// name, in the order the server listed them.
    private static func decoded(_ listed: [MailboxInfo]) -> [MailboxInfo] {
        MailboxInfo.merged(listed.map { MailboxInfo(name: ModifiedUTF7.decode($0.name), attributes: $0.attributes) })
    }

    /// One page of the messages in `mailbox` that match `filter` (all of them
    /// when it is empty), newest message first. Page 1 holds the newest `limit`
    /// messages. A page past the end is empty, not an error.
    public func list(
        mailbox: String = defaultMailbox,
        filter: MessageFilter = MessageFilter(),
        page: Int = 1,
        limit: Int = defaultPageLimit
    ) async throws -> MessagePage {
        guard page >= 1 else {
            throw IrisError.invalidPage(page)
        }
        guard limit >= 1 else {
            throw IrisError.invalidLimit(limit)
        }
        return try await withClient { client in
            let status = try await examine(mailbox, with: client)
            // Without a filter, a page is a range of sequence numbers. With one, it
            // is the same range of positions in the sorted matching UIDs: UIDs grow
            // in arrival order, as sequence numbers do.
            let matches: [UInt32]?
            if filter.isEmpty {
                matches = nil
            } else {
                matches = try await client.searchUIDs(matching: filter).sorted()
            }
            let count = matches?.count ?? status.messageCount
            var messages: [MessageSummary] = []
            var hasMore = false
            if let range = MessagePage.sequenceRange(messageCount: count, page: page, limit: limit) {
                let envelopes: [MessageEnvelope]
                if let matches {
                    envelopes = try await client.fetchEnvelopes(uids: Array(matches[(range.lowerBound - 1)..<range.upperBound]))
                } else {
                    envelopes = try await client.fetchEnvelopes(sequenceNumbers: range)
                }
                messages = envelopes
                    .sorted { $0.sequenceNumber > $1.sequenceNumber }
                    .map { MessageSummary(envelope: $0, account: account.name, mailbox: mailbox) }
                hasMore = range.lowerBound > 1
            }
            return MessagePage(
                mailbox: mailbox,
                filter: filter,
                messages: messages,
                totalCount: count,
                page: page,
                limit: limit,
                hasMore: hasMore
            )
        }
    }

    /// The raw RFC 822 bytes of the message `id`. Reading it does not mark the
    /// message as read. A missing message throws `unknownMessage`. `id` must
    /// name this reader's account: resolve the reader's account from `id.account`.
    public func rawMessage(_ id: IrisID) async throws -> Data {
        precondition(id.account == account.name, "\(id) is not in the account \(account.name)")
        // UIDs start at 1; the server would answer UID 0 with BAD.
        guard id.uid >= 1 else {
            throw IrisError.unknownMessage(id)
        }
        return try await withClient { client in
            _ = try await examine(id.mailbox, with: client)
            return try await fetchRawMessage(id, with: client)
        }
    }

    /// The most message IDs in one Message-ID SEARCH of `thread`. Zoho gave
    /// wrong answers for large OR trees of HEADER keys, so each search stays small.
    static let messageIDSearchChunkSize = 10

    /// The special-use attributes of the mailboxes that `thread` searches, next
    /// to INBOX and the input message's mailbox, in the order that picks the
    /// copy of a message that is in several mailboxes.
    static let threadMailboxAttributes = [#"\Sent"#, #"\Drafts"#, #"\Archive"#, #"\All"#]

    /// Every message in the thread of the message `id`, each once, oldest first.
    /// `id` must name this reader's account, as for `rawMessage(_:)`.
    ///
    /// A message is in the thread when it has `id`'s subject (see
    /// `ThreadSubject`: a subject change starts a new thread) and names a
    /// message ID of the thread in its Message-ID, In-Reply-To, or References.
    /// iris searches INBOX, each `\Sent`, `\Drafts`, `\Archive`, and `\All`
    /// mailbox, and `id`'s mailbox, and reads only the headers of what it finds:
    ///
    /// 1. One SUBJECT search per mailbox, `id`'s first, for `id`'s subject.
    ///    Servers such as Zoho never match a HEADER search on In-Reply-To or
    ///    References, so the subject is the only way to find the replies, and
    ///    every member has it. When the server refuses the whole subject, iris
    ///    searches for its ASCII words instead (`subjectSearches(for:)`). A
    ///    search that is refused, or that does not find `id` in its own
    ///    mailbox, is not used again in this walk; when none is left, iris
    ///    logs one line and searches the rest of the mailboxes by Message-ID.
    /// 2. Every message read with the subject that names a known ID joins
    ///    the thread and adds the IDs it names, until none joins: iPhone Mail
    ///    puts only the parent in References, so the links go one step at a time.
    /// 3. Only in the mailboxes with no SUBJECT search: HEADER Message-ID
    ///    searches, first for the IDs that `id` names, then, round after round,
    ///    for the known IDs that no message read so far has. These find only
    ///    the messages that a known message names, so from one branch of a
    ///    thread they never reach another.
    ///
    /// A message in several mailboxes is shown once, by its Message-ID, from
    /// the first mailbox in the order of `threadMailboxes(listed:inputMailbox:)`
    /// (the lowest UID, when a mailbox has two copies). When the SUBJECT
    /// searches run, every message of a thread that lies in the usual
    /// mailboxes gives the same thread, with the same iris IDs; a start in
    /// another mailbox adds that mailbox to the search. The order is the
    /// `Date:` header, else the date the server received the message, as in
    /// `list`. Other messages cannot name a message that has no Message-ID
    /// header, so its thread is that message alone.
    ///
    /// Only EXAMINE, SEARCH, and `BODY.PEEK` fetches: no message is marked as read.
    public func thread(_ id: IrisID) async throws -> [ThreadMessage] {
        precondition(id.account == account.name, "\(id) is not in the account \(account.name)")
        guard id.uid >= 1 else {
            throw IrisError.unknownMessage(id)
        }
        return try await withClient { client in
            _ = try await examine(id.mailbox, with: client)
            guard let input = try await client.fetchThreadHeaders(uids: [id.uid]).first(where: { $0.uid == id.uid }) else {
                throw IrisError.unknownMessage(id)
            }
            guard let inputMessageID = input.messageID else {
                return [ThreadMessage(irisID: id, rawMessage: try await threadDownload(id, with: client), isInput: true)]
            }

            let mailboxes = Self.threadMailboxes(listed: Self.decoded(try await client.listMailboxes()), inputMailbox: id.mailbox)
            let subject = ThreadSubject.normalized(input.subject)
            // Every message whose headers were read, in the thread or not, so none is read twice.
            var fetched: [IrisID: ThreadHeaders] = [id: input]

            /// Reads the headers of the messages `uids` in the open mailbox, `mailbox`, that are not read yet.
            func readHeaders(_ uids: [UInt32], in mailbox: String) async throws {
                let unread = Set(uids.filter { fetched[threadCopy(mailbox, $0)] == nil })
                guard !unread.isEmpty else {
                    return
                }
                // A UID that was not asked for, such as from an unsolicited FETCH, is skipped.
                for headers in try await client.fetchThreadHeaders(uids: unread.sorted()) where unread.contains(headers.uid) {
                    fetched[threadCopy(mailbox, headers.uid)] = headers
                }
            }

            /// The messages in the open mailbox whose Message-ID is one of `ids`, a few IDs per SEARCH.
            func messageIDMatches(_ ids: [String]) async throws -> [UInt32] {
                var matches: [UInt32] = []
                for start in stride(from: 0, to: ids.count, by: Self.messageIDSearchChunkSize) {
                    let chunk = Array(ids[start..<min(start + Self.messageIDSearchChunkSize, ids.count)])
                    matches += try await client.searchUIDs(messageIDs: chunk)
                }
                return matches
            }

            // The SUBJECT searches still to try. One that is refused, or that
            // misses `id` in its own mailbox, is dropped for the rest of the walk.
            var subjectSearches = Self.subjectSearches(for: subject)
            if subjectSearches.isEmpty {
                IrisLog.log(
                    "The message has no subject to search for, so iris followed only the message IDs "
                        + "that the messages name, and the thread may miss replies."
                )
            }

            /// The messages in the open mailbox, `mailbox`, that the first
            /// SUBJECT search left finds. Nil when none is left.
            func subjectMatches(in mailbox: String) async throws -> [UInt32]? {
                while let texts = subjectSearches.first {
                    let failure: String
                    do {
                        let matches = try await client.searchUIDs(subjectContainingAll: texts)
                        if mailbox != id.mailbox || matches.contains(id.uid) {
                            return matches
                        }
                        failure = "the search did not find the message itself"
                    } catch IrisError.searchFailed(_, let reason) {
                        failure = reason
                    }
                    subjectSearches.removeFirst()
                    if subjectSearches.isEmpty {
                        IrisLog.log(
                            "The server could not search by subject (\(failure)), so iris followed only the message IDs "
                                + "that the messages name, and the thread may miss replies."
                        )
                    }
                }
                return nil
            }

            // 1. One SUBJECT search per mailbox, `id`'s mailbox first: it is open,
            // and its answer must have `id`. A mailbox with no SUBJECT search is
            // searched by the Message-IDs that `id` names instead.
            let firstIDs = input.linkedMessageIDs
            var messageIDMailboxes: [String] = []
            for mailbox in [id.mailbox] + mailboxes.filter({ $0 != id.mailbox }) {
                if mailbox != id.mailbox {
                    _ = try await examine(mailbox, with: client)
                }
                if let matches = try await subjectMatches(in: mailbox) {
                    try await readHeaders(matches, in: mailbox)
                } else {
                    messageIDMailboxes.append(mailbox)
                    try await readHeaders(try await messageIDMatches(firstIDs), in: mailbox)
                }
            }

            // 2. Every message with the subject that names a known ID joins, until
            // none joins. In the mailboxes with no SUBJECT search, each round
            // searches the known IDs that no message read so far has.
            var members: Set<IrisID> = [id]
            var knownIDs = Set(firstIDs)
            var searchedIDs = Set(firstIDs)
            while true {
                var joined = true
                while joined {
                    joined = false
                    for (copy, headers) in fetched where !members.contains(copy)
                        && ThreadSubject.normalized(headers.subject) == subject
                        && !knownIDs.isDisjoint(with: headers.linkedMessageIDs) {
                        members.insert(copy)
                        knownIDs.formUnion(headers.linkedMessageIDs)
                        joined = true
                    }
                }
                let readIDs = Set(fetched.values.compactMap(\.messageID))
                let newIDs = knownIDs.subtracting(searchedIDs).subtracting(readIDs).sorted()
                guard !messageIDMailboxes.isEmpty, !newIDs.isEmpty else {
                    break
                }
                searchedIDs.formUnion(newIDs)
                for mailbox in messageIDMailboxes {
                    _ = try await examine(mailbox, with: client)
                    try await readHeaders(try await messageIDMatches(newIDs), in: mailbox)
                }
            }

            // One copy per Message-ID: the first in mailbox order, then the lowest UID.
            let rank = Dictionary(uniqueKeysWithValues: mailboxes.enumerated().map { ($0.element, $0.offset) })
            func precedes(_ lhs: IrisID, _ rhs: IrisID) -> Bool {
                (rank[lhs.mailbox] ?? rank.count, lhs.uid) < (rank[rhs.mailbox] ?? rank.count, rhs.uid)
            }
            // A reply without a Message-ID has nothing to match its copies by, so each copy is kept.
            var chosen: [String: IrisID] = [:]
            for copy in members {
                let key = fetched[copy]?.messageID ?? copy.description
                if let current = chosen[key], precedes(current, copy) {
                    continue
                }
                chosen[key] = copy
            }

            // Fetched in mailbox order, so each mailbox is opened once.
            let inputCopy = chosen[inputMessageID]
            var messages: [ThreadMessage] = []
            var openMailbox: String?
            for copy in chosen.values.sorted(by: precedes) {
                if copy.mailbox != openMailbox {
                    _ = try await examine(copy.mailbox, with: client)
                    openMailbox = copy.mailbox
                }
                let rawMessage = try await threadDownload(copy, with: client)
                if case .failure = rawMessage {
                    // After a timeout SwiftMail opens a new connection, where no mailbox is open.
                    openMailbox = nil
                }
                messages.append(ThreadMessage(irisID: copy, rawMessage: rawMessage, isInput: copy == inputCopy))
            }
            func date(_ message: ThreadMessage) -> Date {
                let headers = fetched[message.irisID]
                return headers?.date ?? headers?.internalDate ?? .distantPast
            }
            return messages.sorted { lhs, rhs in
                date(lhs) == date(rhs) ? precedes(lhs.irisID, rhs.irisID) : date(lhs) < date(rhs)
            }
        }
    }

    /// The SUBJECT searches that `thread` tries for `subject`, a normalized
    /// subject, in order: the whole subject, then its ASCII words (see
    /// `ThreadSubject.asciiWords(_:)`), for a server that refuses the whole
    /// subject. None for an empty subject, which every message would match.
    static func subjectSearches(for subject: String) -> [[String]] {
        guard !subject.isEmpty else {
            return []
        }
        let words = ThreadSubject.asciiWords(subject)
        return words.isEmpty || words == [subject] ? [[subject]] : [[subject], words]
    }

    /// The raw bytes of `id` from the open mailbox, which must be `id`'s
    /// mailbox, or the error of this one message: it did not download in time,
    /// or it is gone. Every other error, such as a lost connection, throws.
    private func threadDownload(
        _ id: IrisID, with client: any MailClient
    ) async throws -> Result<Data, ThreadMessage.DownloadFailure> {
        do {
            return .success(try await fetchRawMessage(id, with: client))
        } catch IrisError.messageDownloadTimedOut(let seconds) {
            return .failure(.timedOut(seconds: seconds))
        } catch IrisError.unknownMessage {
            return .failure(.gone)
        }
    }

    /// The iris ID of `uid` in `mailbox` of this account.
    private func threadCopy(_ mailbox: String, _ uid: UInt32) -> IrisID {
        IrisID(account: account.name, mailbox: mailbox, uid: uid)
    }

    /// The mailboxes that `thread` searches, each once, in this order: INBOX,
    /// the `\Sent`, `\Drafts`, `\Archive`, and `\All` mailboxes (each kind in
    /// the order of `listed`), then `inputMailbox`. Besides `inputMailbox`,
    /// only names in `listed` are searched. The names are in the form that an
    /// `IrisID` holds, so they compare with `IrisID.mailbox`.
    ///
    /// - Parameter listed: The mailboxes with decoded names, merged, in the order the server listed them.
    private static func threadMailboxes(listed: [MailboxInfo], inputMailbox: String) -> [String] {
        let inbox = listed.filter { IrisID.canonicalMailbox($0.name) == defaultMailbox }
        let special = threadMailboxAttributes.flatMap { attribute in
            listed.filter { $0.attributes.contains(attribute) }
        }
        var names: [String] = []
        for name in (inbox + special).map(\.name) + [inputMailbox] {
            let name = IrisID.canonicalMailbox(name)
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    /// The raw bytes of `id` from the open mailbox, which must be `id`'s
    /// mailbox. A missing message throws `unknownMessage`.
    private func fetchRawMessage(_ id: IrisID, with client: any MailClient) async throws -> Data {
        let data = try await client.fetchRawMessage(uid: id.uid)
        guard !data.isEmpty else {
            throw IrisError.unknownMessage(id)
        }
        return data
    }

    /// Opens `mailbox`, a name as `mailboxes()` shows it, by its wire name in
    /// modified UTF-7. An `unknownMailbox` error holds `mailbox`, the name the
    /// user typed, not the wire name.
    private func examine(_ mailbox: String, with client: any MailClient) async throws -> MailboxStatus {
        do {
            return try await client.examine(mailbox: ModifiedUTF7.encode(mailbox))
        } catch IrisError.unknownMailbox(let account, _, let reason) {
            throw IrisError.unknownMailbox(account: account, name: mailbox, reason: reason)
        }
    }

    /// Runs `body` with a logged-in client, and logs out after it, also when
    /// the login or `body` throws.
    func withClient<T>(_ body: (any MailClient) async throws -> T) async throws -> T {
        let client = makeClient(account)
        return try await client.session { try await body(client) }
    }
}
