import Foundation
@testable import IrisKit

/// A `MailClient` with scripted answers. It records every call, so tests can
/// check what the reader asked for and that it logged out.
actor FakeMailClient: MailClient {
    enum Call: Equatable {
        case login
        case capabilities
        case listMailboxes
        case examine(String)
        case fetchEnvelopes(ClosedRange<Int>)
        case fetchRawMessage(UInt32)
        case logout
    }

    enum Method: Hashable {
        case login, capabilities, listMailboxes, examine, fetchEnvelopes, fetchRawMessage
    }

    private(set) var calls: [Call] = []

    private let accountName: String
    private let capabilityList: [String]
    private let mailboxList: [MailboxInfo]
    private let statuses: [String: MailboxStatus]
    private let envelopes: [MessageEnvelope]
    private let rawMessages: [UInt32: Data]
    private let errors: [Method: any Error]

    /// Mailbox names are wire names (modified UTF-7), as in `MailClient`:
    /// `mailboxes` holds them, `statuses` is keyed by them, and `examine` throws
    /// `unknownMailbox` with the wire name, as SwiftMailClient does, for a name
    /// that is not in `statuses`. `fetchEnvelopes` returns the `envelopes` whose
    /// sequence number is in the range, in the order given. `fetchRawMessage`
    /// returns empty data for a UID that is not in `rawMessages`, as SwiftMail
    /// does. `accountName` goes in the errors the fake throws itself.
    init(
        accountName: String = "work",
        capabilities: [String] = [],
        mailboxes: [MailboxInfo] = [],
        statuses: [String: MailboxStatus] = [:],
        envelopes: [MessageEnvelope] = [],
        rawMessages: [UInt32: Data] = [:],
        errors: [Method: any Error] = [:]
    ) {
        self.accountName = accountName
        self.capabilityList = capabilities
        self.mailboxList = mailboxes
        self.statuses = statuses
        self.envelopes = envelopes
        self.rawMessages = rawMessages
        self.errors = errors
    }

    /// A fake whose INBOX holds `count` messages: sequence number n has UID 100 + n.
    static func inbox(count: Int) -> FakeMailClient {
        FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: count, uidValidity: 7, uidNext: UInt32(101 + count))],
            envelopes: (0..<count).map { envelope(sequenceNumber: $0 + 1) }
        )
    }

    static func envelope(
        sequenceNumber: Int,
        seen: Bool = true,
        from: MailAddress? = MailAddress(name: "Jane Doe", address: "jane@example.com"),
        subject: String? = nil,
        date: Date? = nil,
        internalDate: Date? = nil
    ) -> MessageEnvelope {
        MessageEnvelope(
            sequenceNumber: sequenceNumber,
            uid: UInt32(100 + sequenceNumber),
            seen: seen,
            from: from,
            subject: subject ?? "Message \(sequenceNumber)",
            date: date,
            internalDate: internalDate
        )
    }

    func login() async throws {
        try record(.login, .login)
    }

    func capabilities() async throws -> [String] {
        try record(.capabilities, .capabilities)
        return capabilityList
    }

    func listMailboxes() async throws -> [MailboxInfo] {
        try record(.listMailboxes, .listMailboxes)
        return mailboxList
    }

    func examine(mailbox: String) async throws -> MailboxStatus {
        try record(.examine(mailbox), .examine)
        guard let status = statuses[mailbox] else {
            throw IrisError.unknownMailbox(account: accountName, name: mailbox, reason: "NO no such mailbox")
        }
        return status
    }

    func fetchEnvelopes(sequenceNumbers: ClosedRange<Int>) async throws -> [MessageEnvelope] {
        try record(.fetchEnvelopes(sequenceNumbers), .fetchEnvelopes)
        return envelopes.filter { sequenceNumbers.contains($0.sequenceNumber) }
    }

    func fetchRawMessage(uid: UInt32) async throws -> Data {
        try record(.fetchRawMessage(uid), .fetchRawMessage)
        return rawMessages[uid] ?? Data()
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
