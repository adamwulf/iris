import Foundation

/// The IMAP calls that `iris draft` makes to save a draft, and the only write
/// call in iris (APPEND). It is apart from `MailClient`, so `MailReader`,
/// which every read-only command uses, cannot save anything. `SwiftMailClient`
/// talks to a real server; tests use a fake.
///
/// A client serves one session: `login()`, then the other calls, then
/// `logout()`. `DraftWriter` keeps that order and always logs out. Mailbox
/// names are wire names, in modified UTF-7, as in `MailClient`.
protocol DraftClient: Sendable {
    /// Connects to the server and logs in.
    func login() async throws
    /// Every mailbox with its special-use attributes, by wire name, as
    /// `MailClient.listMailboxes()` gives them. A name can appear more than once.
    func listMailboxes() async throws -> [MailboxInfo]
    /// Saves `draft` in `mailbox` (a wire name) with APPEND and the `\Draft`
    /// flag. Returns the new message's UID from APPENDUID, or nil when the
    /// server does not report it (it has no UIDPLUS). A `draftMayBeSaved`
    /// error holds `mailbox`.
    func appendDraft(_ draft: DraftMessage, to mailbox: String) async throws -> UInt32?
    /// Logs out and closes the connection. It is safe to call after a failed
    /// login, and it never throws.
    func logout() async
}
