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
    /// without the bodies, and each message's size (RFC822.SIZE). A UID that
    /// the open mailbox does not have is left out. `uids` is not empty.
    func fetchThreadHeaders(uids: [UInt32]) async throws -> [ThreadHeaders]
    /// The size, the header fields that iris shows, and the parts of the
    /// message with this UID in the open mailbox, before anything of it is
    /// downloaded (`show` and `download` both start with it): one UID FETCH of
    /// RFC822.SIZE, BODYSTRUCTURE, and `BODY.PEEK[HEADER.FIELDS (...)]`, so
    /// `\Seen` is never set. Nil when the open mailbox has no message with
    /// this UID; the parts are empty when the server's answer has no
    /// BODYSTRUCTURE that SwiftMail can read.
    func fetchOutline(uid: UInt32) async throws -> MessageOutline?
    /// The raw RFC 822 bytes of one message, fetched with `BODY.PEEK[]` so `\Seen`
    /// is never set. Empty when the open mailbox has no message with this UID.
    func fetchRawMessage(uid: UInt32) async throws -> Data
    /// The bytes of the part `id` of the message with this UID in the open
    /// mailbox, fetched with `BODY.PEEK[<section>]` so `\Seen` is never set.
    /// They are still in the part's Content-Transfer-Encoding. A timeout is
    /// `attachmentDownloadTimedOut`.
    func fetchPart(_ id: AttachmentID, uid: UInt32) async throws -> Data
    /// The same fetch for a body part (text/plain or text/html) of a message
    /// that iris shows in parts, which has its own error: a timeout is
    /// `bodyDownloadTimedOut`.
    func fetchBodyPart(_ id: AttachmentID, uid: UInt32) async throws -> Data
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
    /// The flags of one UID, or nil when it does not exist. Used before
    /// replacing a draft: the mailbox name alone never proves it is a draft.
    func fetchFlags(uid: UInt32) async throws -> [String]?
    /// Adds only `\Deleted` to one UID, after its replacement was saved.
    func setDeleted(uid: UInt32) async throws
    /// UID EXPUNGE of exactly one UID. The caller must first require UIDPLUS;
    /// there must never be a fallback to mailbox-wide EXPUNGE.
    func expunge(uid: UInt32) async throws
    /// Saves `draft` in `mailbox` (a wire name) with APPEND and the flags
    /// `\Seen \Draft`. Returns the new message's UID from APPENDUID, or nil when the
    /// server does not report it (it has no UIDPLUS). A `draftMayBeSaved`
    /// error holds `mailbox`.
    func appendDraft(_ draft: DraftMessage, to mailbox: String) async throws -> UInt32?
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

/// What one FETCH (UID RFC822.SIZE BODYSTRUCTURE and the header fields)
/// reports about a message before iris downloads it. Its size decides how
/// iris downloads it (see `MailReader.wholeDownloadLimit`), and for a large
/// message its headers and parts are what iris shows without the whole
/// message. `download` finds the part to fetch in its parts.
struct MessageOutline: Sendable, Equatable {
    /// The size of the whole message in bytes (RFC822.SIZE). Nil when the
    /// server's answer has none.
    let size: Int?
    let headers: MessageHeaders
    /// The parts from BODYSTRUCTURE, in section order: each part that is not
    /// a multipart, and after a message/rfc822 part, the parts of the message
    /// inside it. Empty when the answer has no BODYSTRUCTURE that SwiftMail
    /// can read.
    let parts: [PartOutline]
}

/// The header fields of a message that `iris show` shows. Message IDs have
/// angle brackets, for example `<abc@example.com>`. A missing header is nil
/// or empty.
struct MessageHeaders: Sendable, Equatable {
    /// The `Message-ID` header.
    let messageID: String?
    let subject: String?
    let from: [MailAddress]
    let to: [MailAddress]
    let cc: [MailAddress]
    let replyTo: [MailAddress]
    /// The `Date` header, set by the sender.
    let date: Date?
    /// The first message ID in `In-Reply-To`.
    let inReplyTo: String?
    /// The message IDs in `References`, oldest first.
    let references: [String]

    init(
        messageID: String? = nil,
        subject: String? = nil,
        from: [MailAddress] = [],
        to: [MailAddress] = [],
        cc: [MailAddress] = [],
        replyTo: [MailAddress] = [],
        date: Date? = nil,
        inReplyTo: String? = nil,
        references: [String] = []
    ) {
        self.messageID = messageID
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.replyTo = replyTo
        self.date = date
        self.inReplyTo = inReplyTo
        self.references = references
    }
}

/// One part of a message as BODYSTRUCTURE describes it, without its bytes:
/// what `download` needs to fetch and decode it, and what the decoder needs
/// to tell the body from the other parts.
struct PartOutline: Sendable, Equatable {
    /// The part's section, which `BODY[<section>]` fetches.
    let id: AttachmentID
    /// The MIME type, with only the `charset` parameter (SwiftMail keeps no
    /// other), for example `text/plain; charset=utf-8`.
    let contentType: String
    /// The Content-Disposition type, such as `attachment` or `inline`.
    let disposition: String?
    /// The Content-Transfer-Encoding, such as `BASE64`. Nil when the part has none.
    let encoding: String?
    /// The filename that SwiftMail found, which can also be one it made up
    /// (see "Large messages" in AGENTS.md).
    let filename: String?
    /// The Content-ID.
    let contentID: String?
    /// The size of the part's body as the message holds it, transfer-encoded
    /// (BODYSTRUCTURE's body-fld-octets). Nil when it is not known.
    let size: Int?

    init(
        id: AttachmentID,
        contentType: String,
        disposition: String? = nil,
        encoding: String? = nil,
        filename: String? = nil,
        contentID: String? = nil,
        size: Int? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.disposition = disposition
        self.encoding = encoding
        self.filename = filename
        self.contentID = contentID
        self.size = size
    }
}

/// The headers of one message that `iris thread` follows, as FETCH (UID
/// INTERNALDATE RFC822.SIZE and the header fields) reports them. Message IDs
/// have angle brackets, for example `<abc@example.com>`.
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
    /// The size of the whole message in bytes (RFC822.SIZE), which decides how
    /// `thread` downloads it. Nil when the server's answer has none.
    let size: Int?

    init(
        uid: UInt32,
        messageID: String?,
        inReplyTo: String?,
        references: [String],
        subject: String?,
        date: Date?,
        internalDate: Date?,
        size: Int? = nil
    ) {
        self.uid = uid
        self.messageID = messageID
        self.inReplyTo = inReplyTo
        self.references = references
        self.subject = subject
        self.date = date
        self.internalDate = internalDate
        self.size = size
    }

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
