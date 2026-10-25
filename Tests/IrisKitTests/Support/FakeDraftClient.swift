import Foundation
@testable import IrisKit

/// A `DraftClient` with scripted answers. It records every call, so tests can
/// check what the writer saved, where, and that it logged out.
actor FakeDraftClient: DraftClient {
    enum Call: Equatable {
        case login
        case listMailboxes
        case appendDraft(DraftMessage, String)
        case logout
    }

    enum Method: Hashable {
        case login, listMailboxes, appendDraft
    }

    private(set) var calls: [Call] = []

    private let mailboxList: [MailboxInfo]
    private let appendedUID: UInt32?
    private let errors: [Method: any Error]

    /// `mailboxes` holds wire names (modified UTF-7), as in `DraftClient`.
    /// `appendDraft` returns `appendedUID`: nil stands for a server without UIDPLUS.
    init(mailboxes: [MailboxInfo] = [], appendedUID: UInt32? = nil, errors: [Method: any Error] = [:]) {
        self.mailboxList = mailboxes
        self.appendedUID = appendedUID
        self.errors = errors
    }

    func login() async throws {
        try record(.login, .login)
    }

    func listMailboxes() async throws -> [MailboxInfo] {
        try record(.listMailboxes, .listMailboxes)
        return mailboxList
    }

    func appendDraft(_ draft: DraftMessage, to mailbox: String) async throws -> UInt32? {
        try record(.appendDraft(draft, mailbox), .appendDraft)
        return appendedUID
    }

    func logout() async {
        calls.append(.logout)
    }

    private func record(_ call: Call, _ method: Method) throws {
        calls.append(call)
        if let error = errors[method] {
            throw error
        }
    }
}
