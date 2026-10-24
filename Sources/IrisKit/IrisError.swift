import Foundation

/// The one error type that IrisKit throws. Each message tells the user what to do next.
public enum IrisError: Error, Equatable, LocalizedError {
    /// No `IRIS_<NAME>_IMAP_*` setting was found.
    case noAccountsConfigured
    /// `--account` or `IRIS_DEFAULT_ACCOUNT` named an account that has no settings.
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
    /// The HTML body could not be converted to Markdown.
    case htmlNotConverted(reason: String)

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
        case .htmlNotConverted(let reason):
            return "The HTML body of the message could not be converted to Markdown (\(reason)). "
                + "Run the command again with --body text."
        }
    }

    private static func availableSentence(_ names: [String]) -> String {
        names.isEmpty
            ? "No accounts are configured."
            : "Configured accounts: \(names.joined(separator: ", "))."
    }
}
