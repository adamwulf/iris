import Foundation
import SwiftMail

/// The real `MailClient`, over SwiftMail's `IMAPServer`. It only converts types
/// and errors. The logic is in `MailReader`, where the tests cover it.
struct SwiftMailClient: MailClient {
    /// `IMAPServer.fetchRawMessage` always gives up after this many seconds.
    static let rawMessageTimeoutSeconds = 10

    private let account: Account
    private let server: IMAPServer

    init(account: Account) {
        self.account = account
        // Never send the password in clear text: port 143 must upgrade with
        // STARTTLS, and every other port uses TLS from the first byte.
        // SwiftMail's `.automatic` goes on in plain text on 143 when the server
        // has no STARTTLS, and refuses every port but 143 and 993.
        self.server = IMAPServer(
            host: account.host,
            port: account.port,
            transportSecurity: account.port == 143 ? .startTLS : .implicitTLS
        )
    }

    func login() async throws {
        do {
            try await server.connect()
        } catch {
            throw connectionFailed(error)
        }
        try await run("LOGIN") {
            try await server.login(username: account.username, password: account.password)
        }
    }

    func capabilities() async throws -> [String] {
        let capabilities = try await run("CAPABILITY") {
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
        let specialUse = try await run("LIST") {
            try await server.listSpecialUseMailboxes()
        }
        let all = await server.mailboxes
        return (all + specialUse).map(MailboxInfo.init(swiftMail:))
    }

    func examine(mailbox: String) async throws -> MailboxStatus {
        do {
            let selection = try await server.examineMailbox(mailbox)
            return MailboxStatus(
                messageCount: selection.messageCount,
                uidValidity: selection.uidValidity.value,
                uidNext: selection.uidNext.value
            )
        } catch IMAPError.selectFailed(let reason) {
            throw IrisError.unknownMailbox(name: mailbox, reason: Self.redacting(account.password, in: reason))
        } catch {
            throw irisError(for: error, command: "EXAMINE")
        }
    }

    func fetchEnvelopes(sequenceNumbers: ClosedRange<Int>) async throws -> [MessageEnvelope] {
        let range = SequenceNumber(sequenceNumbers.lowerBound)...SequenceNumber(sequenceNumbers.upperBound)
        let infos = try await run("FETCH") {
            try await server.fetchMessageInfos(sequenceRange: range, options: [.envelope, .internalDate])
        }
        // FETCH always asks for the UID, so a message without one is a server bug. Skip it.
        return infos.compactMap { info in
            guard let uid = info.uid else {
                return nil
            }
            let sender = info.fromAddresses.mailboxes.first
            return MessageEnvelope(
                sequenceNumber: Int(info.sequenceNumber.value),
                uid: uid.value,
                from: sender.map { MailAddress(name: $0.name, address: $0.address) },
                subject: info.subject,
                date: info.date,
                internalDate: info.internalDate
            )
        }
    }

    func fetchRawMessage(uid: UInt32) async throws -> Data {
        do {
            // SwiftMail 88c45cbd (1.16.0) fixes FetchRawMessageCommand.timeoutSeconds
            // at 10, and no public API sends BODY.PEEK[] with a longer timeout.
            return try await server.fetchRawMessage(identifier: UID(uid))
        } catch IMAPError.timeout {
            throw IrisError.messageDownloadTimedOut(uid: uid, seconds: Self.rawMessageTimeoutSeconds)
        } catch {
            throw irisError(for: error, command: "FETCH")
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
    private func run<T>(_ command: String, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw irisError(for: error, command: command)
        }
    }

    private func irisError(for error: any Error, command: String) -> IrisError {
        switch error {
        case let error as IrisError:
            return error
        case IMAPError.loginFailed(let reason), IMAPError.authFailed(let reason):
            return .loginFailed(
                account: account.name,
                username: account.username,
                host: account.host,
                reason: Self.redacting(account.password, in: reason)
            )
        case IMAPError.timeout:
            return connectionFailed(reason: "the server did not answer \(command) in time")
        case IMAPError.connectionFailed, IMAPError.greetingFailed:
            return connectionFailed(error)
        case let error as IMAPError:
            return .serverError(command: command, reason: Self.redacting(account.password, in: error.description))
        default:
            // SwiftNIO errors: DNS, TCP, and TLS failures.
            return connectionFailed(error)
        }
    }

    private func connectionFailed(_ error: any Error) -> IrisError {
        connectionFailed(reason: Self.reason(of: error))
    }

    private func connectionFailed(reason: String) -> IrisError {
        .connectionFailed(
            account: account.name,
            host: account.host,
            port: account.port,
            reason: Self.redacting(account.password, in: reason)
        )
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

private extension MailboxInfo {
    /// The special-use attributes iris shows. SwiftMail's `.inbox` is left out:
    /// SwiftMail adds it to INBOX itself, and it is not an RFC 6154 attribute.
    static let specialUseNames: [(attribute: Mailbox.Info.Attributes, name: String)] = [
        (.all, #"\All"#),
        (.archive, #"\Archive"#),
        (.drafts, #"\Drafts"#),
        (.flagged, #"\Flagged"#),
        (.important, #"\Important"#),
        (.junk, #"\Junk"#),
        (.sent, #"\Sent"#),
        (.trash, #"\Trash"#),
    ]

    init(swiftMail info: Mailbox.Info) {
        self.init(
            name: info.name,
            attributes: Self.specialUseNames.filter { info.attributes.contains($0.attribute) }.map(\.name)
        )
    }
}
