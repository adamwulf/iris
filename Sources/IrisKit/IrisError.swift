import Foundation

/// The one error type that IrisKit throws. Each message tells the user what to do next.
public enum IrisError: Error, Equatable, LocalizedError {
    /// No `IRIS_<NAME>_IMAP_*` setting was found.
    case noAccountsConfigured
    /// `--account`, or the account in an iris ID, named an account that has no settings. A bad
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

    // Drafts

    /// `iris draft` got its reply body both as an argument and with `--file`.
    case draftBodyGivenTwice
    /// `iris draft` got no reply body, and stdin is a terminal.
    case draftBodyMissing
    /// The reply body is empty or only whitespace. `source` says where it came
    /// from, such as `the file "reply.md"`.
    case draftBodyEmpty(source: String)
    /// The reply body could not be read from a file or from stdin.
    case draftBodyNotRead(source: String, reason: String)
    /// The reply body is not UTF-8 text.
    case draftBodyNotUTF8(source: String)
    /// The account has no `IRIS_<NAME>_FROM`, and its username is not an address.
    case draftFromAddressMissing(account: String, username: String)
    /// LIST found no mailbox with the `\Drafts` attribute.
    case draftsMailboxNotFound(account: String)
    /// The draft is larger than the server's APPENDLIMIT.
    case draftTooLarge(account: String, size: Int, limit: Int)
    /// APPEND timed out, or the connection broke during it, so the server may
    /// have saved the draft. `mailbox` is the Drafts mailbox: the wire name
    /// from `SwiftMailClient`, and the decoded name after `DraftWriter`.
    case draftMayBeSaved(account: String, mailbox: String, reason: String)

    // IMAP

    /// The server refused the username or password.
    case loginFailed(account: String, username: String, host: String, reason: String)
    /// iris could not reach the server, or the connection broke before the login worked.
    case connectionFailed(account: String, host: String, port: Int, reason: String)
    /// After a good login, the connection broke: the server closed it, or the network dropped.
    case connectionLost(account: String, command: String, reason: String)
    /// EXAMINE or SELECT failed: the mailbox does not exist, or the server cannot open it.
    case unknownMailbox(account: String, name: String, reason: String)
    /// The mailbox has no message with this iris ID's UID.
    case unknownMessage(IrisID)
    /// The text is not an iris ID, `<account>/<mailbox>/<UID>`.
    case invalidIrisID(String)
    /// `--page` is less than 1.
    case invalidPage(Int)
    /// `--limit` is less than 1.
    case invalidLimit(Int)
    /// `--since` or `--before` is not a day iris can search for.
    case invalidDate(String)
    /// The raw message did not arrive inside SwiftMail's fixed time limit.
    case messageDownloadTimedOut(seconds: Int)
    /// After a good login, the server did not answer a command in time.
    case serverTimedOut(account: String, command: String)
    /// The server answered the SEARCH for the `list` filter options with NO or BAD.
    case searchFailed(account: String, reason: String)
    /// The server answered a command with NO or BAD.
    case serverError(account: String, command: String, reason: String)

    // Google sign-in

    /// `iris auth status` found no account with `IRIS_<NAME>_GOOGLE_CLIENT_ID`.
    case noGoogleAccounts
    /// The account signs in with Google (it has `IRIS_<NAME>_GOOGLE_CLIENT_ID`)
    /// but has no refresh token yet.
    case googleNotSignedIn(account: String)
    /// Google refused the refresh token (`invalid_grant`): the sign-in expired or was revoked.
    case googleSignInExpired(account: String)
    /// Google refused the OAuth client (`invalid_client`, `unauthorized_client`, or `deleted_client`).
    case googleClientRejected(account: String, reason: String)
    /// Getting a token from Google failed for another reason: another answer,
    /// an answer iris cannot read, or a network error.
    case googleTokenFailed(account: String, reason: String)
    /// The browser part of `iris auth login` did not finish: access was denied,
    /// the answer did not match the request, or the time ran out.
    case googleSignInFailed(account: String, reason: String)
    /// Google finished the sign-in but sent no refresh token.
    case googleNoRefreshToken(account: String)
    /// The IMAP server refused AUTHENTICATE XOAUTH2 with a fresh access token.
    case googleLoginRefused(account: String, username: String, host: String, reason: String)

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
                + "Check that the iris ID is correct. If it is, the message may be damaged."
        case .htmlNotConverted(let reason, let hasTextPart):
            let problem = "The HTML body of the message could not be converted to Markdown (\(reason))"
            return hasTextPart
                ? problem + ". Run the command again with --body text."
                : problem + ", and the message has no text part. "
                    + "Run the command again with --format raw to see the message source."
        // Drafts
        case .draftBodyGivenTwice:
            return "The reply was given twice: as an argument and with -F. "
                + "Give it one way: as an argument, with -F <path>, or on stdin."
        case .draftBodyMissing:
            return "No reply was given. Give the reply in Markdown as an argument "
                + "(iris draft '<iris-id>' 'Thanks!'), with -F <path> (-F - reads stdin), "
                + "or on stdin (echo 'Thanks!' | iris draft '<iris-id>')."
        case .draftBodyEmpty(let source):
            return "The reply from \(source) is empty. Write the reply in Markdown, "
                + "and give it as an argument, with -F <path>, or on stdin."
        case .draftBodyNotRead(let source, let reason):
            // In parentheses: Foundation's reasons end with a period.
            return "Could not read the reply from \(source) (\(reason)). "
                + "Check the path, or give the reply as an argument or on stdin."
        case .draftBodyNotUTF8(let source):
            return "The reply from \(source) is not UTF-8 text. Save it as UTF-8, or give the reply as an argument."
        case .draftFromAddressMissing(let account, let username):
            let key = AccountResolver.fromKey(account: account)
            return "iris needs your email address for the From line of the draft, and the username of "
                + "account \"\(account)\" (\"\(username)\") is not an address. Set \(key) to your address, "
                + "for example \"\(key)=Your Name <you@example.com>\", as an environment variable "
                + "or in a .env file in this directory or a parent directory."
        case .draftsMailboxNotFound(let account):
            return "The server has no mailbox marked \\Drafts (account \"\(account)\"), so iris does not know "
                + "where to save the draft. Run `iris mailboxes --account \(MessagePage.shellQuoted(account))` "
                + "to see the mailboxes and their attributes."
        case .draftTooLarge(let account, let size, let limit):
            return "The draft is \(size) bytes, and the server takes at most \(limit) bytes "
                + "(account \"\(account)\"). Shorten the reply, or leave out the quoted message with --no-quote."
        case .draftMayBeSaved(let account, let mailbox, let reason):
            let list = MessagePage.listCommand(
                account: account, mailbox: mailbox, page: 1, limit: MailReader.defaultPageLimit, format: .listDefault
            )
            return "Saving the draft did not finish (account \"\(account)\"): \(reason). "
                + "The server may have saved it in \"\(mailbox)\" anyway: look in it (`\(list)`) before you try again."
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
        case .connectionLost(let account, let command, let reason):
            return "The connection to the server broke during \(command) (account \"\(account)\"): \(reason). "
                + "The network may have dropped, or the server may have closed the connection. Try again."
        case .unknownMailbox(let account, let name, let reason):
            return "The server could not open the mailbox \"\(name)\" (account \"\(account)\"): \(reason). "
                + "Run `iris mailboxes --account \(MessagePage.shellQuoted(account))` to see the mailbox names."
        case .unknownMessage(let id):
            let list = MessagePage.listCommand(
                account: id.account, mailbox: id.mailbox, page: 1, limit: MailReader.defaultPageLimit, format: .listDefault
            )
            return "There is no message \"\(id)\". Run `\(list)` to see the iris IDs."
        case .invalidIrisID(let text):
            return "\"\(text)\" is not an iris ID. An iris ID is <account>/<mailbox>/<UID>, "
                + "for example 'work/INBOX/4821'. Put the iris ID in single quotes: a mailbox name can have spaces "
                + "or [ ], which the shell would change. Run `iris list` to see the iris IDs."
        case .invalidPage(let page):
            return "The page number must be 1 or more, not \(page). Page 1 has the newest messages."
        case .invalidLimit(let limit):
            return "The limit must be 1 or more, not \(limit)."
        case .invalidDate(let text):
            return "\"\(text)\" is not a date. Type a day as YYYY-MM-DD, for example 2026-10-24, "
                + "from the year \(CalendarDay.years.lowerBound) to \(CalendarDay.years.upperBound)."
        case .messageDownloadTimedOut(let seconds):
            return "The message did not download in \(seconds) seconds. It may be large, or the connection "
                + "may be slow. This is a known limit of SwiftMail, the IMAP library that iris uses: it stops "
                + "every raw-message download after \(seconds) seconds. Try again on a faster connection."
        case .serverTimedOut(let account, let command):
            return "The server did not answer \(command) in time (account \"\(account)\"). "
                + "The connection may be slow, or the server may be busy. Try again."
        case .searchFailed(let account, let reason):
            return "The server refused the search for the filter options (account \"\(account)\"): \(reason). "
                + "Some servers refuse --from or --subject text that is not ASCII: try ASCII text. "
                + "Else try again with fewer filter options to find the one that the server refuses."
        case .serverError(let account, let command, let reason):
            return "The server answered \(command) with an error (account \"\(account)\"): \(reason). "
                + "Run `iris check --account \(MessagePage.shellQuoted(account))` to test the account settings."
        // Google sign-in
        case .noGoogleAccounts:
            return "No account signs in with Google. To sign in with Google, add the lines "
                + "\"\(AccountResolver.key(.googleClientID, account: "NAME"))=...\" and "
                + "\"\(AccountResolver.key(.googleClientSecret, account: "NAME"))=...\" to a .env file, "
                + "then run `iris auth login --account <name>`. See \"Gmail with OAuth\" in README.md."
        case .googleNotSignedIn(let account):
            return "\(AccountResolver.key(.googleRefreshToken, account: account)) is not set. "
                + "Run `\(Self.authLoginCommand(account))` to sign in."
        case .googleSignInExpired(let account):
            return "The Google sign-in of the account \"\(account)\" has expired or was revoked "
                + "(Google answered invalid_grant). A Google Cloud app in Testing mode signs you out every 7 days. "
                + "Run `\(Self.authLoginCommand(account))` to sign in again."
        case .googleClientRejected(let account, let reason):
            return "Google refused the OAuth client of the account \"\(account)\": \(reason). "
                + "Check \(AccountResolver.key(.googleClientID, account: account)) and "
                + "\(AccountResolver.key(.googleClientSecret, account: account)): they must be the client ID and "
                + "the client secret of an OAuth client of type \"Desktop app\" in the Google Cloud console."
        case .googleTokenFailed(let account, let reason):
            return "Could not get a token from Google for the account \"\(account)\": \(reason). "
                + "Check your network connection and try again. "
                + "If it keeps failing, run `\(Self.authLoginCommand(account))` to sign in again."
        case .googleSignInFailed(let account, let reason):
            return "The Google sign-in of the account \"\(account)\" did not finish: \(reason). "
                + "Run `\(Self.authLoginCommand(account))` to try again."
        case .googleNoRefreshToken(let account):
            return "Google signed in the account \"\(account)\" but sent no refresh token, so iris cannot stay "
                + "signed in. At https://myaccount.google.com/permissions, remove the access of your Google Cloud "
                + "app (the app name you chose in the Google Cloud console), then run "
                + "`\(Self.authLoginCommand(account))` again."
        case .googleLoginRefused(let account, let username, let host, let reason):
            return "The server \(host) refused the Google sign-in for \(username) (account \"\(account)\"): \(reason). "
                + "Check that \(AccountResolver.key(.username, account: account)) is the address you chose "
                + "when you signed in to Google, then run `\(Self.authLoginCommand(account))` again."
        }
    }

    /// The command that signs `account` in to Google.
    private static func authLoginCommand(_ account: String) -> String {
        "iris auth login --account \(MessagePage.shellQuoted(account))"
    }

    private static func availableSentence(_ names: [String]) -> String {
        names.isEmpty
            ? "No accounts are configured."
            : "Configured accounts: \(names.joined(separator: ", "))."
    }
}
