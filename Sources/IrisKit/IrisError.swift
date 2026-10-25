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
    case draftRecipientsMissing
    case draftRecipientInvalid(option: String, value: String)
    case draftSubjectInvalid
    /// Only a live message with the Draft flag can be updated.
    case notADraft(IrisID)
    /// Safe replacement needs targeted UID EXPUNGE, never mailbox-wide EXPUNGE.
    case draftUpdateNeedsUIDPlus(account: String)
    /// The source cannot be represented without losing its content.
    case draftNotPreserved(reason: String)
    /// APPEND did not finish; the original has not been touched.
    case draftUpdateMayBeSaved(original: IrisID, reason: String)
    /// APPEND succeeded, but its UID was missing or removing the original failed.
    case draftUpdateIncomplete(original: IrisID, replacement: IrisID?, reason: String)

    /// `iris draft` got its body both as an argument and with `--file`.
    case draftBodyGivenTwice
    /// `iris draft` got no body, and stdin is a terminal.
    case draftBodyMissing
    /// The draft body is empty or only whitespace. `source` says where it came
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
    /// from `SwiftMailClient`, and the decoded name after `MailWriter`.
    case draftMayBeSaved(account: String, mailbox: String, reason: String)
    /// A file given with `iris draft reply --attach` is missing or cannot be read.
    case draftAttachmentNotRead(path: String, reason: String)
    /// A path given with `iris draft reply --attach` is a folder, not a file.
    case draftAttachmentIsAFolder(path: String)
    /// With `--attach`, the reply argument names a file or folder that exists:
    /// most likely a second path after one `--attach` (`--attach a.pdf b.pdf`,
    /// or a glob that matched more than one file).
    case draftBodyNamesAFile(path: String)
    /// The server answered APPEND with NO or BAD: for example a draft too large
    /// for a server that announces no APPENDLIMIT, or a full mailbox. `mailbox`
    /// is the Drafts mailbox: the wire name from `SwiftMailClient`, and the
    /// decoded name after `MailWriter`.
    case draftRefused(account: String, mailbox: String, reason: String)

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
    /// A body part of a large message, which iris downloads in parts, did not
    /// arrive inside SwiftMail's fixed time limit for one part.
    case bodyDownloadTimedOut(seconds: Int)
    /// The server sent no bytes for a body part of a large message that
    /// BODYSTRUCTURE says is not empty.
    case bodyNotReceived(IrisID)
    /// After a good login, the server did not answer a command in time.
    case serverTimedOut(account: String, command: String)
    /// The server answered the SEARCH for the `list` filter options with NO or BAD.
    case searchFailed(account: String, reason: String)
    /// The server answered a command with NO or BAD.
    case serverError(account: String, command: String, reason: String)

    // Attachments

    /// The text is not an attachment ID: dot-separated numbers, each 1 or more.
    case invalidAttachmentID(String)
    /// The message has no part with this attachment ID.
    case unknownAttachment(IrisID, AttachmentID)
    /// The server's answer to FETCH BODYSTRUCTURE had none that iris can read.
    case attachmentStructureMissing(IrisID)
    /// The part did not arrive inside SwiftMail's fixed time limit for one part.
    case attachmentDownloadTimedOut(seconds: Int)
    /// The server sent no bytes for a part that BODYSTRUCTURE says is not empty.
    case attachmentNotReceived(IrisID, AttachmentID)
    /// `iris download` has no `-o`, and stdout is a terminal, which the bytes would garble.
    case attachmentStdoutIsTerminal
    /// `iris download -o` names an existing folder, not the file to write.
    case attachmentOutputIsFolder(path: String)
    /// The file that `iris download -o` would write already exists.
    case attachmentFileExists(path: String)
    /// `iris download -o` could not write the file for another reason.
    case attachmentNotSaved(path: String, reason: String)

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
        case .draftRecipientsMissing:
            return "No To recipient was given. Pass --to <address> once for each recipient."
        case .draftRecipientInvalid(let option, let value):
            // Escape controls so a pasted newline cannot add a log line.
            return "The recipient \(String(reflecting: value)) for \(option) is not one email address. "
                + "Give one address, optionally with a display name, "
                + "such as 'Jane Doe <jane@example.com>', without control characters. Repeat \(option) for each recipient."
        case .draftSubjectInvalid:
            return "The draft subject must contain text and no control characters. Pass --subject 'Your subject' on one line."
        case .notADraft(let id):
            return "\(id) is not an editable draft (it needs the \\Draft flag and must not be deleted). "
                + "Use `iris draft reply \(MessagePage.shellQuoted(id.description)) 'Your reply'` to create a reply, "
                + "or choose an existing draft in your mail app."
        case .draftUpdateNeedsUIDPlus(let account):
            return "The server for account \"\(account)\" does not support UIDPLUS. "
                + "iris cannot safely remove only the old draft. Edit the draft in your mail app; nothing was changed."
        case .draftNotPreserved(let reason):
            return "iris cannot preserve this draft: \(reason). Nothing was changed. Edit it in your mail app."
        case .draftUpdateMayBeSaved(let original, let reason):
            return "Saving the replacement for \(original) did not finish: \(reason). "
                + "The original was not removed, but a replacement may exist in \"\(original.mailbox)\". "
                + "Inspect that mailbox in your mail app before retrying, to avoid duplicate drafts."
        case .draftUpdateIncomplete(let original, let replacement, let reason):
            let saved = replacement.map { " as \($0)" } ?? " in \"\(original.mailbox)\" (the server reported no usable replacement iris ID)"
            return "The replacement draft was saved\(saved), but updating \(original) did not finish: \(reason). "
                + "Inspect both drafts in your mail app before retrying. Keep the replacement and remove the old draft "
                + "if it remains; the old draft may already be marked deleted."
        case .draftBodyGivenTwice:
            return "The draft body was given twice: as an argument and with -F. "
                + "Give it one way: as an argument, with -F <path>, or on stdin."
        case .draftBodyMissing:
            return "No draft body was given. Give the body in Markdown as an argument "
                + "(iris draft new --to you@example.com --subject 'Hello' 'Body', "
                + "iris draft reply '<iris-id>' 'Thanks!', or iris draft update '<iris-id>' 'Updated text'), "
                + "with -F <path> (-F - reads stdin), or on stdin."
        case .draftBodyEmpty(let source):
            return "The draft body from \(source) is empty. Write the body in Markdown, "
                + "and give it as an argument, with -F <path>, or on stdin."
        case .draftBodyNotRead(let source, let reason):
            // In parentheses: Foundation's reasons end with a period.
            return "Could not read the draft body from \(source) (\(reason)). "
                + "Check the path, or give the body as an argument or on stdin."
        case .draftBodyNotUTF8(let source):
            return "The draft body from \(source) is not UTF-8 text. Save it as UTF-8, or give the body as an argument."
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
                + "(account \"\(account)\"). Shorten the body or reduce attachments in your mail app; for draft reply, "
                + "leave out the quoted message with --no-quote."
        case .draftMayBeSaved(let account, let mailbox, let reason):
            let list = MessagePage.listCommand(
                account: account, mailbox: mailbox, page: 1, limit: MailReader.defaultPageLimit, format: .listDefault
            )
            return "Saving the draft did not finish (account \"\(account)\"): \(reason). "
                + "The server may have saved it in \"\(mailbox)\" anyway: look in it (`\(list)`) before you try again."
        case .draftAttachmentNotRead(let path, let reason):
            // In parentheses: Foundation's reasons end with a period.
            return "Could not read the file \"\(path)\" to attach it (\(reason)). "
                + "Check the path (a relative path starts in the current directory) and that you can read the file."
        case .draftAttachmentIsAFolder(let path):
            return "\"\(path)\" is a folder, and --attach takes a file. "
                + "Give --attach once for each file in the folder, or attach a .zip of it."
        case .draftBodyNamesAFile(let path):
            return "The draft body is \"\(path)\", which is the name of a file. Each --attach takes one path, "
                + "so a second path after it (or the second file that a pattern such as *.pdf matched) "
                + "becomes the body. Give --attach once for each file, as in --attach a.pdf --attach b.pdf, "
                + "and give a body that is in a file with -F <path>."
        case .draftRefused(let account, let mailbox, let reason):
            return "The server refused to save the draft in \"\(mailbox)\" (account \"\(account)\"): \(reason). "
                + "The usual cause is the draft's size: shorten the body or reduce attachments in your mail app. For draft reply, leave out the quoted "
                + "message with --no-quote. A full mailbox is another: make room, then try again."
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
        case .bodyDownloadTimedOut(let seconds):
            return "The body of the message did not download in \(seconds) seconds. The message is large, so iris "
                + "downloads only its text and HTML parts, and they may be large too, or the connection may be slow. "
                + "This is a known limit of SwiftMail, the IMAP library that iris uses: it stops every part "
                + "download after \(seconds) seconds. Try again on a faster connection."
        case .bodyNotReceived(let id):
            return "The server sent no bytes for the body of the message \"\(id)\", which is not empty. Try again."
        case .serverTimedOut(let account, let command):
            return "The server did not answer \(command) in time (account \"\(account)\"). "
                + "The connection may be slow, or the server may be busy. Try again."
        case .searchFailed(let account, let reason):
            return "The server refused the search for the filter options (account \"\(account)\"): \(reason). "
                + "Some servers refuse filter text that is not ASCII: try ASCII text. "
                + "Else try again with fewer filter options to find the one that the server refuses."
        case .serverError(let account, let command, let reason):
            return "The server answered \(command) with an error (account \"\(account)\"): \(reason). "
                + "Run `iris check --account \(MessagePage.shellQuoted(account))` to test the account settings."
        // Attachments
        case .invalidAttachmentID(let text):
            return "\"\(text)\" is not an attachment ID. An attachment ID is the number that `iris show` lists "
                + "first on each attachment line, such as 2 or 1.2: numbers of 1 or more, joined by dots. "
                + "Run `iris show '<iris-id>'` to see the attachment IDs of a message."
        case .unknownAttachment(let id, let attachment):
            return "The message \"\(id)\" has no attachment \(attachment). "
                + "Run `iris show \(id.shellQuoted)` to see its attachment IDs."
        case .attachmentStructureMissing(let id):
            return "The server did not describe the parts of the message \"\(id)\" (its answer had no BODYSTRUCTURE "
                + "that iris can read), so iris cannot find the attachment. Try again. If it keeps failing, "
                + "`iris show \(id.shellQuoted) --format raw` gives the message source, with every attachment in it."
        case .attachmentDownloadTimedOut(let seconds):
            return "The attachment did not download in \(seconds) seconds. It may be large, or the connection "
                + "may be slow. This is a known limit of SwiftMail, the IMAP library that iris uses: it stops "
                + "every attachment download after \(seconds) seconds. Try again on a faster connection."
        case .attachmentNotReceived(let id, let attachment):
            return "The server sent no bytes for attachment \(attachment) of the message \"\(id)\", which is not "
                + "empty, so iris saved nothing. Try again."
        case .attachmentStdoutIsTerminal:
            return "iris writes the attachment's bytes to stdout, and stdout is a terminal, where they would garble "
                + "the screen. Redirect stdout to a file, as in `iris download '<iris-id>' <attachment-id> > <file>`, "
                + "or pass -o <path> to save it to a file (`iris ro download` has no -o)."
        case .attachmentOutputIsFolder(let path):
            let example = MessagePage.singleQuoted((path as NSString).appendingPathComponent("<file name>"))
            return "\"\(path)\" is a folder, and -o takes the path of the file to write. Add a file name, "
                + "such as the filename that `iris show` lists for the attachment: -o \(example)."
        case .attachmentFileExists(let path):
            return "The file \"\(path)\" already exists, and iris never overwrites a file. Pass -o with another path."
        case .attachmentNotSaved(let path, let reason):
            // In parentheses: Foundation's reasons end with a period.
            return "Could not save the attachment to \"\(path)\" (\(reason)). "
                + "Check that the folder exists and that you can write to it, or pass -o with another path."
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
