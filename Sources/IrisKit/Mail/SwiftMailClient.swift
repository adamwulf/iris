import Foundation
import SwiftMail

/// The real `MailClient`, over SwiftMail's `IMAPServer`. It only converts types
/// and errors. The logic is in `MailReader`, where the tests cover it.
struct SwiftMailClient: MailClient {
    /// `IMAPServer.fetchRawMessage` always gives up after this many seconds.
    static let rawMessageTimeoutSeconds = 10

    /// The most envelopes one FETCH asks for. SwiftMail gives every FETCH 10
    /// seconds (`FetchMessageInfoCommand.timeoutSeconds`), so a page is fetched
    /// in chunks. 100 envelopes are tens of kilobytes, which a slow link moves in time.
    static let envelopeChunkSize = 100

    /// The IMAP commands iris sends. The command decides how its errors read.
    enum Command: Equatable {
        case login
        case capability
        case list
        /// `mailbox` is the wire name, in modified UTF-7.
        case examine(mailbox: String)
        case search
        case fetchEnvelopes
        case fetchRawMessage

        /// The command's name in error messages.
        var name: String {
            switch self {
            case .login: return "LOGIN"
            case .capability: return "CAPABILITY"
            case .list: return "LIST"
            case .examine: return "EXAMINE"
            case .search: return "SEARCH"
            case .fetchEnvelopes, .fetchRawMessage: return "FETCH"
            }
        }
    }

    private let account: Account
    private let server: IMAPServer

    init(account: Account) {
        self.account = account
        self.server = IMAPServer(
            host: account.host,
            port: account.port,
            transportSecurity: Self.transportSecurity(forPort: account.port)
        )
    }

    /// Never send the password in clear text: port 143 must upgrade with
    /// STARTTLS, and every other port uses TLS from the first byte.
    /// SwiftMail's `.automatic` goes on in plain text on 143 when the server
    /// has no STARTTLS, and refuses every port but 143 and 993.
    static func transportSecurity(forPort port: Int) -> MailTransportSecurity {
        port == 143 ? .startTLS : .implicitTLS
    }

    func login() async throws {
        do {
            try await server.connect()
        } catch {
            throw Self.connectionFailed(reason: Self.reason(of: error), account: account)
        }
        try await run(.login) {
            try await server.login(username: account.username, password: account.password)
        }
    }

    func capabilities() async throws -> [String] {
        let capabilities = try await run(.capability) {
            try await server.fetchCapabilities()
        }
        return capabilities.map { capability in
            capability.value.map { "\(capability.name)=\($0)" } ?? capability.name
        }
    }

    func listMailboxes() async throws -> [MailboxInfo] {
        // A plain LIST may leave out the special-use attributes (RFC 6154,
        // section 2). listSpecialUseMailboxes sends LIST and keeps its result in
        // `mailboxes`, then sends LIST RETURN (SPECIAL-USE) when the server has
        // SPECIAL-USE; else SwiftMail guesses from names such as "Sent".
        let specialUse = try await run(.list) {
            try await server.listSpecialUseMailboxes()
        }
        let all = await server.mailboxes
        return (all + specialUse).map(MailboxInfo.init(swiftMail:))
    }

    func examine(mailbox: String) async throws -> MailboxStatus {
        let selection = try await run(.examine(mailbox: mailbox)) {
            try await server.examineMailbox(mailbox)
        }
        return MailboxStatus(
            messageCount: selection.messageCount,
            uidValidity: selection.uidValidity.value,
            uidNext: selection.uidNext.value
        )
    }

    func searchUIDs(matching filter: MessageFilter) async throws -> [UInt32] {
        // extendedSearch sends ESEARCH when the server has it, which answers with
        // ranges (101:250), else a plain SEARCH. Both give the matches in `all`.
        let result: ExtendedSearchResult<UID> = try await run(.search) {
            try await server.extendedSearch(criteria: Self.searchCriteria(for: filter), calendar: CalendarDay.calendar)
        }
        return result.all?.toArray().map(\.value) ?? []
    }

    /// The SEARCH keys for `filter`, one per condition; SEARCH needs all of them
    /// to match. The days use `CalendarDay.calendar`, so pass it to SwiftMail.
    static func searchCriteria(for filter: MessageFilter) -> [SearchCriteria] {
        var criteria: [SearchCriteria] = []
        if filter.unread {
            criteria.append(.unseen)
        }
        if filter.flagged {
            criteria.append(.flagged)
        }
        if let from = filter.from {
            criteria.append(.from(from))
        }
        if let subject = filter.subject {
            criteria.append(.subject(subject))
        }
        if let since = filter.since {
            criteria.append(.since(since.start))
        }
        if let before = filter.before {
            criteria.append(.before(before.start))
        }
        return criteria
    }

    func fetchEnvelopes(sequenceNumbers: ClosedRange<Int>) async throws -> [MessageEnvelope] {
        try await fetchEnvelopes(using: SequenceNumberSet(sequenceNumbers))
    }

    func fetchEnvelopes(uids: [UInt32]) async throws -> [MessageEnvelope] {
        try await fetchEnvelopes(using: UIDSet(uids.map(UID.init)))
    }

    private func fetchEnvelopes<T: MessageIdentifier>(using identifiers: MessageIdentifierSet<T>) async throws -> [MessageEnvelope] {
        // The stream sends one FETCH per chunk, and each FETCH has its own deadline.
        let infos = server.fetchMessageInfos(
            using: identifiers,
            options: [.envelope, .internalDate, .flags],
            chunkSize: Self.envelopeChunkSize
        )
        return try await run(.fetchEnvelopes) {
            var envelopes: [MessageEnvelope] = []
            for try await info in infos {
                // FETCH always asks for the UID, so a message without one is a server bug. Skip it.
                if let envelope = MessageEnvelope(swiftMail: info) {
                    envelopes.append(envelope)
                }
            }
            return envelopes
        }
    }

    func fetchRawMessage(uid: UInt32) async throws -> Data {
        // SwiftMail 88c45cbd (1.16.0) fixes FetchRawMessageCommand.timeoutSeconds
        // at 10, and no public API sends BODY.PEEK[] with a longer timeout.
        try await run(.fetchRawMessage) {
            try await server.fetchRawMessage(identifier: UID(uid))
        }
    }

    func logout() async {
        // After a failed connect there is nothing to close, and SwiftMail would
        // connect again to send LOGOUT.
        guard await server.isConnected else {
            return
        }
        do {
            try await server.logout()
        } catch {
            let reason = Self.redacting(account.password, in: Self.reason(of: error))
            IrisLog.log("Logging out of \(account.host) failed (\(reason)). Closing the connection.")
            try? await server.disconnect()
        }
    }

    // MARK: - Errors

    /// Runs one IMAP command and turns its errors into `IrisError`s.
    private func run<T>(_ command: Command, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw Self.irisError(for: error, command: command, account: account)
        }
    }

    /// The `IrisError` for an error that SwiftMail threw while iris sent `command`.
    /// Server text never keeps the account's password.
    static func irisError(for error: any Error, command: Command, account: Account) -> IrisError {
        let password = account.password
        switch (command, error) {
        case (_, let error as IrisError):
            return error
        case (_, IMAPError.loginFailed(let reason)), (_, IMAPError.authFailed(let reason)):
            return .loginFailed(
                account: account.name,
                username: account.username,
                host: account.host,
                reason: redacting(password, in: reason)
            )
        case (.examine(let mailbox), IMAPError.selectFailed(let reason)):
            return .unknownMailbox(account: account.name, name: mailbox, reason: redacting(password, in: reason))
        case (.fetchRawMessage, IMAPError.timeout):
            return .messageDownloadTimedOut(seconds: rawMessageTimeoutSeconds)
        case (.login, IMAPError.timeout):
            return connectionFailed(reason: "the server did not answer \(command.name) in time", account: account)
        case (_, IMAPError.timeout):
            // The login worked, so the host and port are right.
            return .serverTimedOut(account: account.name, command: command.name)
        case (.login, IMAPError.connectionFailed), (_, IMAPError.greetingFailed):
            return connectionFailed(reason: reason(of: error), account: account)
        case (_, IMAPError.connectionFailed):
            // The login worked, so the host and port are right. SwiftMail
            // reports a closed connection and a BYE this way.
            return connectionLost(reason: reason(of: error), command: command, account: account)
        case (_, let error as IMAPError):
            return .serverError(
                account: account.name,
                command: command.name,
                reason: redacting(password, in: error.description)
            )
        case (.login, _):
            // SwiftNIO errors: TCP and TLS failures.
            return connectionFailed(reason: reason(of: error), account: account)
        default:
            // SwiftNIO errors after login, such as a connection reset by the server.
            return connectionLost(reason: reason(of: error), command: command, account: account)
        }
    }

    private static func connectionFailed(reason: String, account: Account) -> IrisError {
        .connectionFailed(
            account: account.name,
            host: account.host,
            port: account.port,
            reason: redacting(account.password, in: reason)
        )
    }

    private static func connectionLost(reason: String, command: Command, account: Account) -> IrisError {
        .connectionLost(account: account.name, command: command.name, reason: redacting(account.password, in: reason))
    }

    private static func reason(of error: any Error) -> String {
        switch error {
        case IMAPError.connectionFailed(let reason), IMAPError.greetingFailed(let reason):
            return reason
        case let error as IMAPError:
            return error.description
        default:
            return String(describing: error)
        }
    }

    /// `text` with every copy of `secret` replaced, in case a server repeats the password.
    static func redacting(_ secret: String, in text: String) -> String {
        secret.isEmpty ? text : text.replacingOccurrences(of: secret, with: "<password>")
    }
}

extension MailboxInfo {
    /// The special-use attributes iris shows. SwiftMail's `.inbox` is left out:
    /// SwiftMail adds it to INBOX itself, and it is not an RFC 6154 attribute.
    private static let specialUseNames: [(attribute: Mailbox.Info.Attributes, name: String)] = [
        (.all, #"\All"#),
        (.archive, #"\Archive"#),
        (.drafts, #"\Drafts"#),
        (.flagged, #"\Flagged"#),
        (.important, #"\Important"#),
        (.junk, #"\Junk"#),
        (.sent, #"\Sent"#),
        (.trash, #"\Trash"#),
    ]

    /// `info` with its wire name, in modified UTF-7, as `MailClient` gives names.
    init(swiftMail info: Mailbox.Info) {
        self.init(
            name: info.name,
            attributes: Self.specialUseNames.filter { info.attributes.contains($0.attribute) }.map(\.name)
        )
    }
}

extension MessageEnvelope {
    /// `info` from FETCH (UID FLAGS ENVELOPE INTERNALDATE). Nil when it has no UID.
    init?(swiftMail info: MessageInfo) {
        guard let uid = info.uid else {
            return nil
        }
        let sender = info.fromAddresses.mailboxes.first
        self.init(
            sequenceNumber: Int(info.sequenceNumber.value),
            uid: uid.value,
            seen: info.flags.contains(.seen),
            from: sender.map { MailAddress(name: $0.name, address: $0.address) },
            subject: info.subject,
            date: info.date,
            internalDate: info.internalDate
        )
    }
}
