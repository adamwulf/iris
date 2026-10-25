import Foundation
import SwiftMail

/// The real `MailClient` and `MailWriteClient`, over SwiftMail's `IMAPServer`.
/// It only converts types and errors. The logic is in `MailReader` and
/// `MailWriter`, where the tests cover it. For an account that signs in with
/// Google, `login()` first gets an access token from `GoogleTokenEndpoint`.
struct SwiftMailClient: MailWriteClient {
    /// `IMAPServer.fetchRawMessage` always gives up after this many seconds.
    static let rawMessageTimeoutSeconds = 10

    /// `IMAPServer.fetchPart` always gives up after this many seconds
    /// (`FetchMessagePartCommand.timeoutSeconds`).
    static let partTimeoutSeconds = 60

    /// The most messages one FETCH of `fetchEnvelopes` or `fetchThreadHeaders`
    /// asks for. SwiftMail gives every FETCH 10 seconds
    /// (`FetchMessageInfoCommand.timeoutSeconds`), so a page is fetched in
    /// chunks. 100 envelopes, or the thread headers of 100 messages, are tens
    /// of kilobytes, which a slow link moves in time.
    static let envelopeChunkSize = 100

    /// The header fields that `fetchThreadHeaders` asks for.
    static let threadHeaderFields = ["Message-ID", "In-Reply-To", "References", "Subject", "Date"]

    /// The IMAP commands iris sends. The command decides how its errors read.
    enum Command: Equatable {
        /// LOGIN with a password.
        case login
        /// AUTHENTICATE XOAUTH2 with a Google access token.
        case authenticate
        case capability
        case list
        /// `mailbox` is the wire name, in modified UTF-7.
        case examine(mailbox: String)
        /// The SEARCH for the `list` filter options, and the SUBJECT search of `thread`.
        case search
        /// The Message-ID SEARCH of `thread`.
        case headerSearch
        case fetchEnvelopes
        case fetchThreadHeaders
        case fetchRawMessage
        case fetchStructure
        case fetchPart
        /// `mailbox` is the wire name, in modified UTF-7.
        case select(mailbox: String)
        case store
        /// `mailbox` is the wire name, in modified UTF-7.
        case append(mailbox: String)

        /// The command's name in error messages.
        var name: String {
            switch self {
            case .login: return "LOGIN"
            case .authenticate: return "AUTHENTICATE"
            case .capability: return "CAPABILITY"
            case .list: return "LIST"
            case .examine: return "EXAMINE"
            case .search, .headerSearch: return "SEARCH"
            case .fetchEnvelopes, .fetchThreadHeaders, .fetchRawMessage, .fetchStructure, .fetchPart: return "FETCH"
            case .select: return "SELECT"
            case .store: return "STORE"
            case .append: return "APPEND"
            }
        }
    }

    private let account: Account
    private let server: IMAPServer
    private let tokenEndpoint: GoogleTokenEndpoint

    /// `transport` reaches Google's token endpoint, for an account that signs in with Google.
    init(account: Account, transport: any HTTPTransport = URLSessionTransport()) {
        self.account = account
        self.server = IMAPServer(
            host: account.host,
            port: account.port,
            transportSecurity: Self.transportSecurity(forPort: account.port)
        )
        self.tokenEndpoint = GoogleTokenEndpoint(transport: transport)
    }

    /// Never send the password in clear text: port 143 must upgrade with
    /// STARTTLS, and every other port uses TLS from the first byte.
    /// SwiftMail's `.automatic` goes on in plain text on 143 when the server
    /// has no STARTTLS, and refuses every port but 143 and 993.
    static func transportSecurity(forPort port: Int) -> MailTransportSecurity {
        port == 143 ? .startTLS : .implicitTLS
    }

    func login() async throws {
        switch account.authentication {
        case .password(let password):
            try await connect()
            try await run(.login) {
                try await server.login(username: account.username, password: password)
            }
        case .google(let client, let refreshToken):
            // Before connecting, so an expired sign-in opens no IMAP connection.
            let accessToken = try await tokenEndpoint.accessToken(
                client: client, refreshToken: refreshToken, account: account.name
            )
            try await connect()
            try await run(.authenticate, alsoRedacting: accessToken) {
                try await server.authenticateXOAUTH2(email: account.username, accessToken: accessToken)
            }
        }
    }

    private func connect() async throws {
        do {
            try await server.connect()
        } catch {
            throw Self.connectionFailed(reason: Self.reason(of: error), account: account, secrets: account.secrets)
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
        if let to = filter.to {
            criteria.append(.to(to))
        }
        if let subject = filter.subject {
            criteria.append(.subject(subject))
        }
        if let search = filter.search {
            criteria.append(.text(search))
        }
        if let since = filter.since {
            criteria.append(.since(since.start))
        }
        if let before = filter.before {
            criteria.append(.before(before.start))
        }
        return criteria
    }

    func searchUIDs(subjectContainingAll texts: [String]) async throws -> [UInt32] {
        // .search, so a refusal is searchFailed, which thread catches.
        let result: ExtendedSearchResult<UID> = try await run(.search) {
            try await server.extendedSearch(criteria: Self.subjectSearchCriteria(texts))
        }
        return result.all?.toArray().map(\.value) ?? []
    }

    /// The SEARCH keys for `texts`: a SUBJECT key per text. SEARCH needs all of them to match.
    static func subjectSearchCriteria(_ texts: [String]) -> [SearchCriteria] {
        texts.map { .subject($0) }
    }

    func searchUIDs(messageIDs: [String]) async throws -> [UInt32] {
        let result: ExtendedSearchResult<UID> = try await run(.headerSearch) {
            try await server.extendedSearch(criteria: [Self.messageIDSearchCriteria(messageIDs)])
        }
        return result.all?.toArray().map(\.value) ?? []
    }

    /// The SEARCH key for `messageIDs`: a HEADER Message-ID key per ID, joined
    /// by OR. The ORs make a balanced tree, so the nesting stays shallow.
    /// `messageIDs` is not empty.
    static func messageIDSearchCriteria(_ messageIDs: [String]) -> SearchCriteria {
        anyOf(messageIDs.map { SearchCriteria.header("Message-ID", $0) }[...])
    }

    /// The key that matches when any of `keys` matches. `keys` is not empty.
    private static func anyOf(_ keys: ArraySlice<SearchCriteria>) -> SearchCriteria {
        guard keys.count > 1 else {
            return keys[keys.startIndex]
        }
        let middle = keys.startIndex + keys.count / 2
        return .or(anyOf(keys[..<middle]), anyOf(keys[middle...]))
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

    func fetchThreadHeaders(uids: [UInt32]) async throws -> [ThreadHeaders] {
        // No ENVELOPE: SwiftMail reads the header fields with the parser that
        // `iris show` uses, and the fields are a few hundred bytes a message.
        let infos = server.fetchMessageInfos(
            using: UIDSet(uids.map(UID.init)),
            options: [.internalDate],
            headerFields: Self.threadHeaderFields,
            chunkSize: Self.envelopeChunkSize
        )
        return try await run(.fetchThreadHeaders) {
            var headers: [ThreadHeaders] = []
            for try await info in infos {
                // FETCH always asks for the UID, so a message without one is a server bug. Skip it.
                if let header = ThreadHeaders(swiftMail: info) {
                    headers.append(header)
                }
            }
            return headers
        }
    }

    func fetchRawMessage(uid: UInt32) async throws -> Data {
        // SwiftMail 88c45cbd (1.16.0) fixes FetchRawMessageCommand.timeoutSeconds
        // at 10, and no public API sends BODY.PEEK[] with a longer timeout.
        try await run(.fetchRawMessage) {
            try await server.fetchRawMessage(identifier: UID(uid))
        }
    }

    func fetchStructure(uid: UInt32) async throws -> [PartStructure]? {
        // One UID FETCH (UID BODYSTRUCTURE), with FetchMessageInfoCommand's 10
        // seconds. IMAPServer.fetchStructure would fail for a missing UID, and
        // sends a second FETCH for the filenames, which iris does not use.
        let infos = try await run(.fetchStructure) {
            try await server.fetchMessageInfosBulk(using: UIDSet(UID(uid)), options: [.bodyStructure])
        }
        return Self.partStructures(in: infos, uid: uid)
    }

    /// The parts that FETCH (UID BODYSTRUCTURE) gave for `uid`, from the one
    /// answer with that UID: an unsolicited FETCH for another message (such as
    /// a flag change) is skipped. Nil when no answer has the UID, so the open
    /// mailbox has no such message. Empty when the answer has no BODYSTRUCTURE
    /// that SwiftMail could read.
    static func partStructures(in infos: [MessageInfo], uid: UInt32) -> [PartStructure]? {
        infos.first { $0.uid?.value == uid }.map { info in
            info.parts.map(PartStructure.init(swiftMail:))
        }
    }

    func fetchPart(_ id: AttachmentID, uid: UInt32) async throws -> Data {
        // One BODY.PEEK[<section>], with SwiftMail's fixed 60-second deadline.
        try await run(.fetchPart) {
            try await server.fetchPart(section: Section(id.components), of: UID(uid))
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
            let reason = Redaction.redacting(account.secrets, in: Self.reason(of: error))
            IrisLog.log("Logging out of \(account.host) failed (\(reason)). Closing the connection.")
            try? await server.disconnect()
        }
    }

    // MARK: - Writes (MailWriteClient)

    func select(mailbox: String) async throws {
        _ = try await run(.select(mailbox: mailbox)) {
            try await server.selectMailbox(mailbox)
        }
    }

    func setSeen(_ seen: Bool, uid: UInt32) async throws {
        try await run(.store) {
            try await server.store(flags: [.seen], on: UIDSet(UID(uid)), operation: Self.storeOperation(seen: seen))
        }
    }

    /// `+FLAGS` adds `\Seen` (read), and `-FLAGS` removes it (unread).
    static func storeOperation(seen: Bool) -> StoreData.StoreType {
        seen ? .add : .remove
    }

    /// The flags a draft gets next to `\Draft`, which `createDraft` adds itself.
    /// `\Seen`, as Apple Mail saves its own drafts: without it, some mail apps
    /// show the new draft as unread in Drafts.
    static let additionalDraftFlags: [Flag] = [.seen]

    func appendDraft(_ draft: DraftMessage, to mailbox: String) async throws -> UInt32? {
        // createDraft adds the \Draft flag and X-Uniform-Type-Identifier:
        // com.apple.mail-draft, which makes Apple Mail treat it as its own draft.
        let result = try await run(.append(mailbox: mailbox)) {
            try await server.createDraft(
                from: Email(draft: draft), in: mailbox, additionalFlags: Self.additionalDraftFlags
            )
        }
        return result.firstUID?.value
    }

    // MARK: - Errors

    /// Runs one IMAP command and turns its errors into `IrisError`s.
    /// `accessToken` is the Google access token that AUTHENTICATE sends.
    private func run<T>(
        _ command: Command,
        alsoRedacting accessToken: String? = nil,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw Self.irisError(for: error, command: command, account: account, accessToken: accessToken)
        }
    }

    /// The `IrisError` for an error that SwiftMail threw while iris sent `command`.
    /// Server text never keeps a secret of the account, nor `accessToken`.
    static func irisError(
        for error: any Error,
        command: Command,
        account: Account,
        accessToken: String? = nil
    ) -> IrisError {
        let secrets = account.secrets + [accessToken].compactMap { $0 }
        func redacted(_ text: String) -> String {
            Redaction.redacting(secrets, in: text)
        }
        switch (command, error) {
        case (_, let error as IrisError):
            return error
        case (.authenticate, IMAPError.loginFailed(let reason)), (.authenticate, IMAPError.authFailed(let reason)):
            // The access token is fresh, so the server refused the address or
            // the scope that the user allowed at sign-in.
            return .googleLoginRefused(
                account: account.name,
                username: account.username,
                host: account.host,
                reason: redacted(reason)
            )
        case (.authenticate, IMAPError.unsupportedAuthMechanism):
            return .invalidSetting(
                key: AccountResolver.key(.host, account: account.name),
                reason: "the server \(account.host) does not offer Google sign-in (AUTH=XOAUTH2). "
                    + "Sign-in with Google works with Gmail, imap.gmail.com."
            )
        case (_, IMAPError.loginFailed(let reason)), (_, IMAPError.authFailed(let reason)):
            return .loginFailed(
                account: account.name,
                username: account.username,
                host: account.host,
                reason: redacted(reason)
            )
        case (.examine(let mailbox), IMAPError.selectFailed(let reason)),
             (.select(let mailbox), IMAPError.selectFailed(let reason)):
            return .unknownMailbox(account: account.name, name: mailbox, reason: redacted(reason))
        case (.fetchRawMessage, IMAPError.timeout):
            return .messageDownloadTimedOut(seconds: rawMessageTimeoutSeconds)
        case (.fetchPart, IMAPError.timeout):
            return .attachmentDownloadTimedOut(seconds: partTimeoutSeconds)
        case (.append, IMAPError.appendLimitExceeded(let size, let limit)):
            return .draftTooLarge(account: account.name, size: size, limit: limit)
        case (.append(let mailbox), IMAPError.timeout):
            // The server may have stored the message before the answer was due.
            return .draftMayBeSaved(
                account: account.name, mailbox: mailbox, reason: "the server did not answer APPEND in time"
            )
        case (.login, IMAPError.timeout), (.authenticate, IMAPError.timeout):
            return connectionFailed(
                reason: "the server did not answer \(command.name) in time", account: account, secrets: secrets
            )
        case (_, IMAPError.timeout):
            // The login worked, so the host and port are right.
            return .serverTimedOut(account: account.name, command: command.name)
        case (.login, IMAPError.connectionFailed), (.authenticate, IMAPError.connectionFailed),
             (_, IMAPError.greetingFailed):
            return connectionFailed(reason: reason(of: error), account: account, secrets: secrets)
        case (.append(let mailbox), IMAPError.connectionFailed):
            return draftMayBeSaved(reason: reason(of: error), mailbox: mailbox, account: account, secrets: secrets)
        case (.append(let mailbox), let error as IMAPError):
            // A tagged NO or BAD (commandFailed). The usual causes are a draft too
            // large for a server that announces no APPENDLIMIT (Zoho), and a full mailbox.
            return .draftRefused(account: account.name, mailbox: mailbox, reason: redacted(error.description))
        case (_, IMAPError.connectionFailed):
            // The login worked, so the host and port are right. SwiftMail
            // reports a closed connection and a BYE this way.
            return connectionLost(reason: reason(of: error), command: command, account: account, secrets: secrets)
        case (.search, let error as IMAPError):
            // The login and EXAMINE worked, so the account is fine, and the cause is
            // usually the filter: NO or BAD (commandFailed), or NO [BADCHARSET] for
            // text that is not ASCII (searchCharsetNotSupported). A busy server can
            // also answer NO; the reason in the message shows that.
            return .searchFailed(account: account.name, reason: redacted(error.description))
        case (_, let error as IMAPError):
            return .serverError(account: account.name, command: command.name, reason: redacted(error.description))
        case (.login, _), (.authenticate, _):
            // SwiftNIO errors: TCP and TLS failures.
            return connectionFailed(reason: reason(of: error), account: account, secrets: secrets)
        case (.append(let mailbox), _):
            // SwiftNIO errors during APPEND, such as a connection reset by the server.
            return draftMayBeSaved(reason: reason(of: error), mailbox: mailbox, account: account, secrets: secrets)
        default:
            // SwiftNIO errors after login, such as a connection reset by the server.
            return connectionLost(reason: reason(of: error), command: command, account: account, secrets: secrets)
        }
    }

    private static func connectionFailed(reason: String, account: Account, secrets: [String]) -> IrisError {
        .connectionFailed(
            account: account.name,
            host: account.host,
            port: account.port,
            reason: Redaction.redacting(secrets, in: reason)
        )
    }

    private static func connectionLost(
        reason: String,
        command: Command,
        account: Account,
        secrets: [String]
    ) -> IrisError {
        .connectionLost(
            account: account.name,
            command: command.name,
            reason: Redaction.redacting(secrets, in: reason)
        )
    }

    private static func draftMayBeSaved(
        reason: String,
        mailbox: String,
        account: Account,
        secrets: [String]
    ) -> IrisError {
        .draftMayBeSaved(account: account.name, mailbox: mailbox, reason: Redaction.redacting(secrets, in: reason))
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
}

extension Email {
    /// `draft` as SwiftMail writes it. `constructContent` adds Date (now), a new
    /// Message-ID, and multipart/alternative with the text and HTML parts.
    /// With attachments, it puts that inside multipart/mixed, followed by one
    /// base64 part per file with `Content-Disposition: attachment`.
    init(draft: DraftMessage) {
        func emailAddress(_ address: MailAddress) -> EmailAddress {
            EmailAddress(name: address.name, address: address.address)
        }
        let attachments = draft.attachments.map { attachment in
            Attachment(filename: attachment.filename, mimeType: attachment.mimeType, data: attachment.data, isInline: false)
        }
        self.init(
            sender: emailAddress(draft.from),
            recipients: draft.to.map(emailAddress),
            ccRecipients: draft.cc.map(emailAddress),
            subject: draft.subject,
            textBody: draft.markdown,
            htmlBody: draft.html,
            attachments: attachments.isEmpty ? nil : attachments
        )
        let headers = draft.threadingHeaders
        additionalHeaders = headers.isEmpty ? nil : headers
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

extension PartStructure {
    /// `part` from BODYSTRUCTURE, as SwiftMail's `[MessagePart](BodyStructure)` gives it.
    /// SwiftMail keeps a message/rfc822 part at its own section, so it can be
    /// fetched whole, and adds the parts inside it after it (`2`, then `2.1`, `2.2`).
    init(swiftMail part: MessagePart) {
        self.init(id: AttachmentID(components: part.section.components), encoding: part.encoding, size: part.size)
    }
}

extension ThreadHeaders {
    /// `info` from FETCH (UID INTERNALDATE and the `threadHeaderFields`). Nil when it has no UID.
    init?(swiftMail info: MessageInfo) {
        guard let uid = info.uid else {
            return nil
        }
        self.init(
            uid: uid.value,
            messageID: info.messageId?.description,
            inReplyTo: info.inReplyTo?.description,
            references: info.references?.map(\.description) ?? [],
            subject: info.subject,
            date: info.date,
            internalDate: info.internalDate
        )
    }
}
