import Foundation

/// The one error type that IrisKit throws. Each message tells the user what to do next.
public enum IrisError: Error, Equatable, LocalizedError {
    /// No `IRIS_<NAME>_IMAP_*` setting was found.
    case noAccountsConfigured
    /// `--account` named an account that has no settings. A bad
    /// `IRIS_DEFAULT_ACCOUNT` gives `invalidSetting` instead.
    case unknownAccount(name: String, available: [String])
    /// Two or more accounts are configured and none was chosen.
    case accountNotChosen(available: [String])
    /// An account is missing a required setting.
    case missingSetting(key: String)
    /// A setting has a value that iris cannot use.
    case invalidSetting(key: String, reason: String)

    // Message rendering

    /// The raw message bytes could not be parsed as an email.
    case messageNotParsed(reason: String)
    /// The HTML body could not be converted to Markdown. `hasTextPart` tells
    /// whether the message has a text part to show instead.
    case htmlNotConverted(reason: String, hasTextPart: Bool)

    // IMAP

    /// The server refused the username or password.
    case loginFailed(account: String, username: String, host: String, reason: String)
    /// iris could not reach the server, or the connection broke.
    case connectionFailed(account: String, host: String, port: Int, reason: String)
    /// EXAMINE failed: the mailbox does not exist, or the server cannot open it.
    case unknownMailbox(account: String, name: String, reason: String)
    /// The open mailbox has no message with this UID.
    case unknownUID(account: String, uid: UInt32, mailbox: String)
    /// `--page` is less than 1.
    case invalidPage(Int)
    /// `--limit` is less than 1.
    case invalidLimit(Int)
    /// The raw message did not arrive inside SwiftMail's fixed time limit.
    case messageDownloadTimedOut(uid: UInt32, seconds: Int)
    /// After a good login, the server did not answer a command in time.
    case serverTimedOut(account: String, command: String)
    /// The server answered a command with NO or BAD.
    case serverError(account: String, command: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noAccountsConfigured:
            return "No email account is configured. Add the lines "
                + "\"\(AccountResolver.key(.host, account: "NAME"))=...\", "
                + "\"\(AccountResolver.key(.username, account: "NAME"))=...\", and "
                + "\"\(AccountResolver.key(.password, account: "NAME"))=...\" "
                + "to a .env file in this directory or a parent directory, or set them as environment variables. "
                + "See README.md for each provider's settings."
        case .unknownAccount(let name, let available):
            return "There is no account named \"\(name)\". " + Self.availableSentence(available)
        case .accountNotChosen(let available):
            return "More than one account is configured. Pass --account <name>, "
                + "or set \(AccountResolver.defaultAccountKey) in .env. " + Self.availableSentence(available)
        case .missingSetting(let key):
            return "Missing setting \(key). Set it as an environment variable, "
                + "or add the line \"\(key)=...\" to a .env file in this directory or a parent directory."
        case .invalidSetting(let key, let reason):
            return "The setting \(key) is not valid: \(reason)"
        // Message rendering
        case .messageNotParsed(let reason):
            return "The message could not be read as an email (\(reason)). "
                + "Check that the UID belongs to a message in this mailbox. If it does, the message may be damaged."
        case .htmlNotConverted(let reason, let hasTextPart):
            let problem = "The HTML body of the message could not be converted to Markdown (\(reason))"
            return hasTextPart
                ? problem + ". Run the command again with --body text."
                : problem + ", and the message has no text part. "
                    + "Run the command again with --format raw to see the message source."
        // IMAP
        case .loginFailed(let account, let username, let host, let reason):
            return "The server \(host) refused the login for \(username) (account \"\(account)\"): \(reason). "
                + "Check \(AccountResolver.key(.username, account: account)) and "
                + "\(AccountResolver.key(.password, account: account)). "
                + "Gmail and iCloud need an app-specific password, not your account password, "
                + "and Zoho needs one when two-factor authentication is on. "
                + "Zoho also needs IMAP turned on in Settings > Mail Accounts."
        case .connectionFailed(let account, let host, let port, let reason):
            return "Could not connect to \(host):\(port) (account \"\(account)\"): \(reason). "
                + "Check your network connection, and check \(AccountResolver.key(.host, account: account)) and "
                + "\(AccountResolver.key(.port, account: account)) (IMAP over TLS uses port \(AccountResolver.defaultPort))."
        case .unknownMailbox(let account, let name, let reason):
            return "The server could not open the mailbox \"\(name)\" (account \"\(account)\"): \(reason). "
                + "Run `iris mailboxes --account \(MessagePage.shellQuoted(account))` to see the mailbox names."
        case .unknownUID(let account, let uid, let mailbox):
            let list = MessagePage.listCommand(account: account, mailbox: mailbox, page: 1, limit: MailReader.defaultPageLimit)
            return "There is no message with UID \(uid) in \"\(mailbox)\" (account \"\(account)\"). "
                + "Run `\(list)` to see the UIDs."
        case .invalidPage(let page):
            return "The page number must be 1 or more, not \(page). Page 1 has the newest messages."
        case .invalidLimit(let limit):
            return "The limit must be 1 or more, not \(limit)."
        case .messageDownloadTimedOut(let uid, let seconds):
            return "Message UID \(uid) did not download in \(seconds) seconds. It may be large, or the connection "
                + "may be slow. This is a known limit of SwiftMail, the IMAP library that iris uses: it stops "
                + "every raw-message download after \(seconds) seconds. Try again on a faster connection."
        case .serverTimedOut(let account, let command):
            return "The server did not answer \(command) in time (account \"\(account)\"). "
                + "The connection may be slow, or the server may be busy. Try again."
        case .serverError(let account, let command, let reason):
            return "The server answered \(command) with an error (account \"\(account)\"): \(reason). "
                + "Run `iris check --account \(MessagePage.shellQuoted(account))` to test the account settings."
        }
    }

    private static func availableSentence(_ names: [String]) -> String {
        names.isEmpty
            ? "No accounts are configured."
            : "Configured accounts: \(names.joined(separator: ", "))."
    }
}
