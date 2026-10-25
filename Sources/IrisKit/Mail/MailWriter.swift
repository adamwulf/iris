import Foundation

/// Changes mail in one account. Each call is one IMAP session, as in
/// `MailReader` (`saveReply` takes two: one reads, one saves): it logs in,
/// does its work, and logs out, also when the work throws.
///
/// The write calls are here and in `MailWriteClient`, never in `MailReader`,
/// so a read-only command cannot reach them. iris never sends mail.
public struct MailWriter: Sendable {
    /// The special-use attribute of the mailbox that drafts go to (RFC 6154).
    static let draftsAttribute = #"\Drafts"#

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

    /// Saves a reply to the message `id` as a draft: `body` (Markdown), then,
    /// with `quote`, the original's body as a quote (see `ReplyComposer`).
    /// `id` must name this writer's account. It takes two sessions: a
    /// `MailReader` reads the original (without marking it as read), then
    /// `saveDraft(_:)` saves the reply.
    public func saveReply(
        to id: IrisID,
        body: String,
        from: MailAddress,
        replyAll: Bool,
        quote: Bool,
        timeZone: TimeZone = .current
    ) async throws -> SavedDraft {
        let reader = MailReader(account: account, makeClient: { makeClient($0) })
        let original = try await MessageDecoder.decode(try await reader.rawMessage(id))
        let draft = ReplyComposer.reply(
            to: original,
            body: body,
            from: from,
            username: account.username,
            replyAll: replyAll,
            quote: quote,
            timeZone: timeZone
        )
        return try await saveDraft(draft)
    }

    /// Saves `draft` with the flags `\Seen \Draft` in the first mailbox that
    /// LIST marks `\Drafts`. A `draftMayBeSaved` error holds the decoded name.
    func saveDraft(_ draft: DraftMessage) async throws -> SavedDraft {
        let client = makeClient(account)
        return try await client.session {
            let mailboxes = MailboxInfo.merged(try await client.listMailboxes())
            guard let drafts = mailboxes.first(where: { $0.attributes.contains(Self.draftsAttribute) }) else {
                throw IrisError.draftsMailboxNotFound(account: account.name)
            }
            let mailbox = ModifiedUTF7.decode(drafts.name)
            let uid: UInt32?
            do {
                uid = try await client.appendDraft(draft, to: drafts.name)
            } catch IrisError.draftMayBeSaved(let account, _, let reason) {
                throw IrisError.draftMayBeSaved(account: account, mailbox: mailbox, reason: reason)
            }
            return SavedDraft(
                mailbox: mailbox,
                irisID: uid.map { IrisID(account: account.name, mailbox: mailbox, uid: $0) }
            )
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

/// Where `iris draft` saved a draft.
public struct SavedDraft: Sendable, Equatable {
    /// The Drafts mailbox, by its decoded name.
    public let mailbox: String
    /// The draft's iris ID. Nil when the server did not report the new UID
    /// (it has no UIDPLUS).
    public let irisID: IrisID?

    /// The note that `iris draft` writes to stderr when there is no iris ID
    /// to print. Nil when there is one.
    public var missingIDNote: String? {
        guard irisID == nil else {
            return nil
        }
        return "The draft was saved in \"\(mailbox)\", but the server did not report its UID, "
            + "so iris cannot give its iris ID."
    }
}
