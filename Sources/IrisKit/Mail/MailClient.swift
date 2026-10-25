import Foundation

/// The IMAP calls that iris makes to read mail. `SwiftMailClient` talks to a
/// real server; tests use a fake. The calls that change mail are in `MailWriteClient`.
///
/// A client serves one session: `login()`, then the other calls, then
/// `logout()`. `session(_:)` keeps that order and always logs out.
///
/// A client knows only wire names, the modified UTF-7 form of mailbox names
/// (RFC 3501, section 5.1.3). `MailReader` and `MailWriter` encode and decode them.
protocol MailClient: Sendable {
    /// Connects to the server and logs in.
    func login() async throws
    /// The capabilities the server reports after login, such as `IMAP4rev1` or `AUTH=PLAIN`.
    func capabilities() async throws -> [String]
    /// Every mailbox with its special-use attributes, by wire name. A name can
    /// appear more than once, each time with some of its attributes;
    /// `MailReader` merges them.
    func listMailboxes() async throws -> [MailboxInfo]
    /// Opens a mailbox read-only (EXAMINE, never SELECT). Later fetches read from it.
    /// `mailbox` is the wire name, and an `unknownMailbox` error holds it.
    func examine(mailbox: String) async throws -> MailboxStatus
    /// The UIDs of the messages in the open mailbox that match every condition
    /// of `filter` (UID SEARCH), in any order. `filter` is not empty.
    func searchUIDs(matching filter: MessageFilter) async throws -> [UInt32]
    /// The UIDs of the messages in the open mailbox whose subject has every one
    /// of `texts`, in any order: one UID SEARCH with a SUBJECT key per text.
    /// A server that refuses the search (NO, BAD, or NO [BADCHARSET]) gives
    /// `searchFailed`. `texts` is not empty.
    func searchUIDs(subjectContainingAll texts: [String]) async throws -> [UInt32]
    /// The UIDs of the messages in the open mailbox whose Message-ID is one of
    /// `messageIDs`, in any order: one UID SEARCH with a HEADER Message-ID key
    /// per ID, joined by OR. `messageIDs` is not empty, and `MailReader` sends
    /// at most `MailReader.messageIDSearchChunkSize` of them.
    func searchUIDs(messageIDs: [String]) async throws -> [UInt32]
    /// UID, flags, envelope, and internal date of the messages with these sequence numbers.
    func fetchEnvelopes(sequenceNumbers: ClosedRange<Int>) async throws -> [MessageEnvelope]
    /// The same for the messages with these UIDs (UID FETCH). `uids` is not empty.
    func fetchEnvelopes(uids: [UInt32]) async throws -> [MessageEnvelope]
    /// The headers that tie the messages with these UIDs to their threads,
    /// fetched with `BODY.PEEK[HEADER.FIELDS (...)]` so `\Seen` is never set,
    /// without the bodies. A UID that the open mailbox does not have is left
    /// out. `uids` is not empty.
    func fetchThreadHeaders(uids: [UInt32]) async throws -> [ThreadHeaders]
    /// The raw RFC 822 bytes of one message, fetched with `BODY.PEEK[]` so `\Seen`
    /// is never set. Empty when the open mailbox has no message with this UID.
    func fetchRawMessage(uid: UInt32) async throws -> Data
    /// Logs out and closes the connection. It is safe to call after a failed
    /// login, and it never throws, so it cannot hide the error that came before it.
    func logout() async
}

/// The IMAP calls that change mail, for `MailWriter`. `MailReader` holds only a
/// `MailClient`, so a read-only command cannot reach them.
protocol MailWriteClient: MailClient {
    /// Opens a mailbox read-write (SELECT), so STORE can change its flags.
    /// `mailbox` is the wire name, and an `unknownMailbox` error holds it.
    func select(mailbox: String) async throws
    /// Adds the `\Seen` flag to the message with this UID in the selected
    /// mailbox (UID STORE +FLAGS), or removes it (-FLAGS) when `seen` is false.
    /// The server answers OK for a missing UID and changes nothing.
    func setSeen(_ seen: Bool, uid: UInt32) async throws
}

extension MailClient {
    /// Logs in, runs `body`, and logs out after it, also when the login or
    /// `body` throws.
    func session<T>(_ body: () async throws -> T) async throws -> T {
        do {
            try await login()
            let result = try await body()
            await logout()
            return result
        } catch {
            await logout()
            throw error
        }
    }
}

/// What EXAMINE reports about a mailbox.
struct MailboxStatus: Sendable, Equatable {
    let messageCount: Int
    let uidValidity: UInt32
    let uidNext: UInt32
}

/// One message as FETCH (UID FLAGS ENVELOPE INTERNALDATE) reports it.
struct MessageEnvelope: Sendable, Equatable {
    let sequenceNumber: Int
    let uid: UInt32
    /// Whether the message has the `\Seen` flag, so it has been read.
    let seen: Bool
    /// The first address of the `From:` header.
    let from: MailAddress?
    let subject: String?
    /// The `Date:` header, set by the sender.
    let date: Date?
    /// When the server received the message (INTERNALDATE).
    let internalDate: Date?
}

/// The headers of one message that `iris thread` follows, as FETCH (UID
/// INTERNALDATE and the header fields) reports them. Message IDs have angle
/// brackets, for example `<abc@example.com>`.
struct ThreadHeaders: Sendable, Equatable {
    let uid: UInt32
    /// The `Message-ID` header. Nil when the message has none.
    let messageID: String?
    /// The `In-Reply-To` header read as one message ID (SwiftMail's
    /// `MessageInfo.inReplyTo`). A header with more than one ID, or with a
    /// comment, gives text that is no real ID, so it links to nothing.
    let inReplyTo: String?
    /// The message IDs in `References`, oldest first.
    let references: [String]
    let subject: String?
    /// The `Date:` header, set by the sender.
    let date: Date?
    /// When the server received the message (INTERNALDATE).
    let internalDate: Date?

    /// Every message ID that this message names: its own, the one it replies
    /// to, and its references, each once, in that order.
    var linkedMessageIDs: [String] {
        var ids: [String] = []
        for id in [messageID, inReplyTo].compactMap({ $0 }) + references where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }
}
