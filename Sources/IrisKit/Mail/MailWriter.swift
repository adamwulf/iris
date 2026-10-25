import Foundation

/// Changes mail in one account. Each call is one IMAP session, as in
/// `MailReader`: it logs in, does its work, and logs out, also when the work throws.
///
/// The write calls are here and in `MailWriteClient`, never in `MailReader`,
/// so a read-only command cannot reach them.
public struct MailWriter: Sendable {
    public let account: Account
    private let makeClient: @Sendable (Account) -> any MailWriteClient

    /// A writer that talks to the account's server through SwiftMail.
    public init(account: Account) {
        self.init(account: account, makeClient: { SwiftMailClient(account: $0) })
    }

    /// A writer that gets its client from `makeClient`, once per call. Tests pass a fake.
    init(account: Account, makeClient: @escaping @Sendable (Account) -> any MailWriteClient) {
        self.account = account
        self.makeClient = makeClient
    }

    /// Marks the message `id` as read: adds its `\Seen` flag. A message that is
    /// already read stays read. A missing message throws `unknownMessage`. `id`
    /// must name this writer's account: resolve the writer's account from `id.account`.
    public func markRead(_ id: IrisID) async throws {
        try await setSeen(true, id)
    }

    /// Marks the message `id` as unread: removes its `\Seen` flag. A message
    /// that is already unread stays unread. A missing message throws
    /// `unknownMessage`. `id` must name this writer's account.
    public func markUnread(_ id: IrisID) async throws {
        try await setSeen(false, id)
    }

    private func setSeen(_ seen: Bool, _ id: IrisID) async throws {
        precondition(id.account == account.name, "\(id) is not in the account \(account.name)")
        // UIDs start at 1; the server would answer UID 0 with BAD.
        guard id.uid >= 1 else {
            throw IrisError.unknownMessage(id)
        }
        let client = makeClient(account)
        try await client.session {
            try await select(id.mailbox, with: client)
            // STORE answers OK for a missing UID, so look for the message first.
            // FETCH (UID FLAGS ENVELOPE INTERNALDATE) does not set \Seen.
            guard try await !client.fetchEnvelopes(uids: [id.uid]).isEmpty else {
                throw IrisError.unknownMessage(id)
            }
            try await client.setSeen(seen, uid: id.uid)
        }
    }

    /// Opens `mailbox` read-write by its wire name in modified UTF-7, as
    /// `MailReader` opens one read-only. An `unknownMailbox` error holds
    /// `mailbox`, the name the user typed, not the wire name.
    private func select(_ mailbox: String, with client: any MailWriteClient) async throws {
        do {
            try await client.select(mailbox: ModifiedUTF7.encode(mailbox))
        } catch IrisError.unknownMailbox(let account, _, let reason) {
            throw IrisError.unknownMailbox(account: account, name: mailbox, reason: reason)
        }
    }
}
