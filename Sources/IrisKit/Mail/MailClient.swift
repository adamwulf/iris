import Foundation

/// The IMAP calls that iris makes. `SwiftMailClient` talks to a real server;
/// tests use a fake.
///
/// A client serves one session: `login()`, then the other calls, then
/// `logout()`. `MailReader` keeps that order and always logs out.
protocol MailClient: Sendable {
    /// Connects to the server and logs in.
    func login() async throws
    /// The capabilities the server reports after login, such as `IMAP4rev1` or `AUTH=PLAIN`.
    func capabilities() async throws -> [String]
    /// Every mailbox with its special-use attributes. A name can appear more
    /// than once, each time with some of its attributes; `MailReader` merges them.
    func listMailboxes() async throws -> [MailboxInfo]
    /// Opens a mailbox read-only (EXAMINE, never SELECT). Later fetches read from it.
    func examine(mailbox: String) async throws -> MailboxStatus
    /// UID, envelope, and internal date of the messages with these sequence numbers.
    func fetchEnvelopes(sequenceNumbers: ClosedRange<Int>) async throws -> [MessageEnvelope]
    /// The raw RFC 822 bytes of one message, fetched with `BODY.PEEK[]` so `\Seen`
    /// is never set. Empty when the open mailbox has no message with this UID.
    func fetchRawMessage(uid: UInt32) async throws -> Data
    /// Logs out and closes the connection. It is safe to call after a failed
    /// login, and it never throws, so it cannot hide the error that came before it.
    func logout() async
}

/// What EXAMINE reports about a mailbox.
struct MailboxStatus: Sendable, Equatable {
    let messageCount: Int
    let uidValidity: UInt32
    let uidNext: UInt32
}

/// One message as FETCH (UID ENVELOPE INTERNALDATE) reports it.
struct MessageEnvelope: Sendable, Equatable {
    let sequenceNumber: Int
    let uid: UInt32
    /// The first address of the `From:` header.
    let from: MailAddress?
    let subject: String?
    /// The `Date:` header, set by the sender.
    let date: Date?
    /// When the server received the message (INTERNALDATE).
    let internalDate: Date?
}
