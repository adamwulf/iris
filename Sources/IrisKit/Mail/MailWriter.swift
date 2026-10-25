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
    /// with `quote`, the original's body as a quote (see `ReplyComposer`),
    /// with `attachments` attached. `id` must name this writer's account. It
    /// takes two sessions: a `MailReader` reads the original (without marking
    /// it as read), then `saveDraft(_:)` saves the reply. A large original is
    /// read as `show` reads it, in parts: the reply needs only its headers and body.
    public func saveReply(
        to id: IrisID,
        body: String,
        from: MailAddress,
        replyAll: Bool,
        quote: Bool,
        attachments: [DraftAttachment] = [],
        timeZone: TimeZone = .current
    ) async throws -> SavedDraft {
        let reader = MailReader(account: account, makeClient: { makeClient($0) })
        // Downloaded and decoded as `show` and `thread` do it, but whole
        // (`--full`): a reply quotes the original with its history, as mail apps do.
        let original = try await MessageFormatter.document(
            message: try await reader.message(id), irisID: id, body: .auto, full: true
        )
        let draft = ReplyComposer.reply(
            to: original,
            body: body,
            from: from,
            username: account.username,
            replyAll: replyAll,
            quote: quote,
            attachments: attachments,
            timeZone: timeZone
        )
        return try await saveDraft(draft)
    }

    /// Replaces a saved draft's body, without adding a quote. Recipients,
    /// threading headers, and attachments come from the original message.
    /// Saves in the same mailbox before removing the old UID. UIDPLUS is
    /// required so no unrelated deleted message can be expunged. Callers must
    /// use the returned iris ID for subsequent operations.
    public func updateDraft(_ id: IrisID, body: String) async throws -> SavedDraft {
        precondition(id.account == account.name, "\(id) is not in the account \(account.name)")
        guard id.uid >= 1 else { throw IrisError.unknownMessage(id) }
        let client = makeClient(account)
        return try await client.session {
            try await select(id.mailbox, with: client)
            guard let flags = try await client.fetchFlags(uid: id.uid) else {
                throw IrisError.unknownMessage(id)
            }
            guard flags.contains(where: { $0.lowercased() == #"\draft"# }),
                  !flags.contains(where: { $0.lowercased() == #"\deleted"# }) else {
                throw IrisError.notADraft(id)
            }
            guard try await client.capabilities().contains(where: { $0.uppercased() == "UIDPLUS" }) else {
                throw IrisError.draftUpdateNeedsUIDPlus(account: account.name)
            }
            // Whole MIME is necessary here: the parts-only show path omits
            // attachment bytes and BODYSTRUCTURE can lose attachment names.
            let raw = try await client.fetchRawMessage(uid: id.uid)
            guard !raw.isEmpty else { throw IrisError.unknownMessage(id) }
            let draft = try DraftUpdater.replacingBody(in: raw, body: body)
            let uid: UInt32?
            do {
                uid = try await client.appendDraft(draft, to: ModifiedUTF7.encode(id.mailbox))
            } catch IrisError.draftMayBeSaved(_, _, let reason) {
                throw IrisError.draftUpdateMayBeSaved(original: id, reason: reason)
            } catch IrisError.draftRefused(let account, _, let reason) {
                throw IrisError.draftRefused(account: account, mailbox: id.mailbox, reason: reason)
            }
            guard let uid, uid > 0, uid != id.uid else {
                throw IrisError.draftUpdateIncomplete(
                    original: id, replacement: nil,
                    reason: "The server did not return a usable APPENDUID; the original was not removed"
                )
            }
            let replacement = IrisID(account: account.name, mailbox: id.mailbox, uid: uid)
            do {
                try await client.setDeleted(uid: id.uid)
                try await client.expunge(uid: id.uid)
            } catch {
                throw IrisError.draftUpdateIncomplete(
                    original: id, replacement: replacement,
                    reason: Redaction.redacting(account.secrets, in: error.localizedDescription)
                )
            }
            return SavedDraft(mailbox: id.mailbox, irisID: replacement)
        }
    }

    /// Saves `draft` with the flags `\Seen \Draft` in the first mailbox that
    /// LIST marks `\Drafts`. A `draftMayBeSaved` or `draftRefused` error holds
    /// the decoded name.
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
            } catch IrisError.draftRefused(let account, _, let reason) {
                throw IrisError.draftRefused(account: account, mailbox: mailbox, reason: reason)
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
