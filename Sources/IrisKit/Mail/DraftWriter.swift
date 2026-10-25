import Foundation

/// Saves replies as drafts in one account's `\Drafts` mailbox. It is the only
/// type in iris that changes the server, and it is apart from `MailReader`,
/// so a read-only command cannot reach it. iris never sends mail.
///
/// A reply takes two IMAP sessions: `MailReader` reads the original, and a
/// `DraftClient` session saves the draft. Each session logs out, also when
/// its work throws.
public struct DraftWriter: Sendable {
    /// The special-use attribute of the mailbox that drafts go to (RFC 6154).
    static let draftsAttribute = #"\Drafts"#

    public let account: Account
    private let reader: MailReader
    private let makeClient: @Sendable (Account) -> any DraftClient

    /// A writer that talks to the account's server through SwiftMail.
    public init(account: Account) {
        self.init(reader: MailReader(account: account), makeClient: { SwiftMailClient(account: $0) })
    }

    /// A writer that reads with `reader`, and gets its draft client from
    /// `makeClient`, once per draft. Tests pass fakes.
    init(reader: MailReader, makeClient: @escaping @Sendable (Account) -> any DraftClient) {
        self.account = reader.account
        self.reader = reader
        self.makeClient = makeClient
    }

    /// Saves a reply to the message `id` as a draft: `body` (Markdown), then,
    /// with `quote`, the original's body as a quote (see `ReplyComposer`).
    /// `id` must name this writer's account. Reading the original does not
    /// mark it as read.
    public func saveReply(
        to id: IrisID,
        body: String,
        from: MailAddress,
        replyAll: Bool,
        quote: Bool,
        timeZone: TimeZone = .current
    ) async throws -> SavedDraft {
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
        return try await save(draft)
    }

    /// Saves `draft` with the `\Draft` flag in the first mailbox that LIST
    /// marks `\Drafts`. A `draftMayBeSaved` error holds the decoded name.
    func save(_ draft: DraftMessage) async throws -> SavedDraft {
        try await withClient { client in
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

    /// Runs `body` with a logged-in client, and logs out after it, also when
    /// the login or `body` throws.
    private func withClient<T>(_ body: (any DraftClient) async throws -> T) async throws -> T {
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
