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
        let decoded = listed.map { MailboxInfo(name: ModifiedUTF7.decode($0.name), attributes: $0.attributes) }
        return MailboxInfo.merged(decoded).sorted(by: MailboxInfo.areInNameOrder)
    }

    /// One page of `mailbox`, newest message first. Page 1 holds the newest
    /// `limit` messages. A page past the end is empty, not an error.
    public func list(
        mailbox: String = defaultMailbox,
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
            var messages: [MessageSummary] = []
            var hasMore = false
            if let range = MessagePage.sequenceRange(messageCount: status.messageCount, page: page, limit: limit) {
                messages = try await client.fetchEnvelopes(sequenceNumbers: range)
                    .sorted { $0.sequenceNumber > $1.sequenceNumber }
                    .map { MessageSummary(envelope: $0, account: account.name, mailbox: mailbox) }
                hasMore = range.lowerBound > 1
            }
            return MessagePage(
                mailbox: mailbox,
                messages: messages,
                totalCount: status.messageCount,
                page: page,
                limit: limit,
                hasMore: hasMore
            )
        }
    }

    /// The raw RFC 822 bytes of the message with `uid` in `mailbox`. Reading it
    /// does not mark the message as read. A missing message throws `unknownMessage`.
    public func rawMessage(uid: UInt32, mailbox: String) async throws -> Data {
        let id = IrisID(account: account.name, mailbox: mailbox, uid: uid)
        // UIDs start at 1; the server would answer UID 0 with BAD.
        guard uid >= 1 else {
            throw IrisError.unknownMessage(id)
        }
        return try await withClient { client in
            _ = try await examine(mailbox, with: client)
            let data = try await client.fetchRawMessage(uid: uid)
            guard !data.isEmpty else {
                throw IrisError.unknownMessage(id)
            }
            return data
        }
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
        do {
            try await client.login()
            let result = try await body(client)
            await client.logout()
            return result
        } catch {
            await client.logout()
            throw error
        }
    }
}
