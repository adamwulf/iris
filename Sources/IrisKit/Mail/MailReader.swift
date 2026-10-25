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

    /// The header fields that `thread` searches for the message IDs it knows.
    static let threadHeaderFields = ["Message-ID", "In-Reply-To", "References"]

    /// The special-use attributes of the mailboxes that `thread` searches, next
    /// to INBOX and the input message's mailbox, in the order that picks the
    /// copy of a message that is in several mailboxes.
    static let threadMailboxAttributes = [#"\Sent"#, #"\Drafts"#, #"\Archive"#, #"\All"#]

    /// Every message in the thread of the message `id`, each once, oldest first.
    /// `id` must name this reader's account, as for `rawMessage(_:)`.
    ///
    /// The thread is found with header searches. iris searches INBOX, each
    /// `\Sent`, `\Archive`, `\Drafts`, and `\All` mailbox, and `id`'s mailbox
    /// for the messages whose Message-ID, In-Reply-To, or References holds a
    /// message ID that `id` names. Each message found adds the message IDs it
    /// names, and the search repeats with the new IDs until a round finds none:
    /// iPhone Mail puts only the parent in References, so one search is not
    /// enough. A message whose subject is not `id`'s subject (see
    /// `ThreadSubject`) is not in the thread, and its IDs are not followed.
    ///
    /// A message in several mailboxes is shown once, by its Message-ID, from
    /// the first mailbox in the order of `threadMailboxes(listed:inputMailbox:)`
    /// (the lowest UID, when a mailbox has two copies). That order does not
    /// depend on `id`, so every message of a thread gives the same thread,
    /// with the same iris IDs. The order is the `Date:` header, else the date the server
    /// received the message, as in `list`. Other messages cannot name a message
    /// that has no Message-ID header, so its thread is that message alone.
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
            guard input.messageID != nil else {
                return [ThreadMessage(irisID: id, rawMessage: try await fetchRawMessage(id, with: client))]
            }

            let mailboxes = Self.threadMailboxes(listed: Self.decoded(try await client.listMailboxes()), inputMailbox: id.mailbox)
            let subject = ThreadSubject.normalized(input.subject)
            // Every message whose headers were fetched, in the thread or not, so none is fetched twice.
            var fetched: [IrisID: ThreadHeaders] = [id: input]
            var members: [IrisID] = [id]
            var searchedIDs: Set<String> = []
            var newIDs = input.linkedMessageIDs
            while !newIDs.isEmpty {
                searchedIDs.formUnion(newIDs)
                var foundIDs: [String] = []
                for mailbox in mailboxes {
                    _ = try await examine(mailbox, with: client)
                    let matches = try await client.searchUIDs(headers: Self.threadHeaderFields, containingAny: newIDs)
                    let unfetched = Set(matches.filter { fetched[threadCopy(mailbox, $0)] == nil })
                    guard !unfetched.isEmpty else {
                        continue
                    }
                    for headers in try await client.fetchThreadHeaders(uids: unfetched.sorted()) {
                        let copy = threadCopy(mailbox, headers.uid)
                        // Skip a UID that was not asked for, such as an unsolicited FETCH.
                        guard unfetched.contains(headers.uid), fetched.updateValue(headers, forKey: copy) == nil else {
                            continue
                        }
                        guard ThreadSubject.normalized(headers.subject) == subject else {
                            continue
                        }
                        members.append(copy)
                        for linked in headers.linkedMessageIDs where !searchedIDs.contains(linked) && !foundIDs.contains(linked) {
                            foundIDs.append(linked)
                        }
                    }
                }
                newIDs = foundIDs
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
            var messages: [ThreadMessage] = []
            var openMailbox: String?
            for copy in chosen.values.sorted(by: precedes) {
                if copy.mailbox != openMailbox {
                    _ = try await examine(copy.mailbox, with: client)
                    openMailbox = copy.mailbox
                }
                messages.append(ThreadMessage(irisID: copy, rawMessage: try await fetchRawMessage(copy, with: client)))
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
