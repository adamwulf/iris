import Foundation

/// Finds the configured accounts and picks the one a command uses.
///
/// Each account is a group of keys with the account's name in the middle:
///
///     IRIS_WORK_IMAP_HOST=imap.zoho.com
///     IRIS_WORK_IMAP_PORT=993            (optional; 993 is the default)
///     IRIS_WORK_IMAP_USERNAME=me@example.com
///     IRIS_WORK_IMAP_PASSWORD=app-password
///     IRIS_DEFAULT_ACCOUNT=work          (optional when only one account exists)
///
/// An account with `IRIS_<NAME>_GOOGLE_CLIENT_ID` signs in with Google
/// (XOAUTH2) instead of a password:
///
///     IRIS_PERSONAL_IMAP_HOST=imap.gmail.com
///     IRIS_PERSONAL_IMAP_USERNAME=me@gmail.com
///     IRIS_PERSONAL_GOOGLE_CLIENT_ID=....apps.googleusercontent.com
///     IRIS_PERSONAL_GOOGLE_CLIENT_SECRET=...
///     IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN=...   (written by `iris auth login`)
///
/// A name is uppercase letters, digits, and underscores in the key, and it may
/// contain underscores because the suffix (`_IMAP_HOST`, ...) is fixed. Users
/// type the name in any case; iris shows it lowercased.
public enum AccountResolver {
    public enum Field: String, CaseIterable, Sendable {
        case host = "IMAP_HOST"
        case port = "IMAP_PORT"
        case username = "IMAP_USERNAME"
        /// Only for an account that does not sign in with Google.
        case password = "IMAP_PASSWORD"
        /// Its presence makes the account sign in with Google.
        case googleClientID = "GOOGLE_CLIENT_ID"
        case googleClientSecret = "GOOGLE_CLIENT_SECRET"
        case googleRefreshToken = "GOOGLE_REFRESH_TOKEN"
    }

    public static let keyPrefix = "IRIS_"
    public static let defaultAccountKey = "IRIS_DEFAULT_ACCOUNT"
    public static let defaultPort = 993

    /// The key that holds `field` for `account`: `key(.host, account: "work")` is `IRIS_WORK_IMAP_HOST`.
    public static func key(_ field: Field, account: String) -> String {
        keyPrefix + account.uppercased() + "_" + field.rawValue
    }

    /// All settings iris can see: the `.env` files, with the process environment
    /// on top (the environment wins). An empty environment value counts as "not set".
    /// Resolve this once at command start, then pass it to the other functions.
    public static func settings(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingIn directory: URL? = nil
    ) -> [String: String] {
        var merged = DotEnv.loadAll(startingIn: directory)
        for (key, value) in environment where !value.isEmpty {
            merged[key] = value
        }
        return merged
    }

    /// The lowercased names of every account that has at least one key of a `Field`, sorted.
    public static func accountNames(in settings: [String: String]) -> [String] {
        Set(settings.keys.compactMap(accountName(fromKey:))).sorted()
    }

    /// The default account's name: `IRIS_DEFAULT_ACCOUNT` if it is set, else the
    /// only configured account, else nil.
    public static func defaultAccountName(in settings: [String: String]) -> String? {
        if let name = settings[defaultAccountKey] {
            return name.lowercased()
        }
        let names = accountNames(in: settings)
        return names.count == 1 ? names[0] : nil
    }

    /// The account a command uses: `name` (from `--account` or an iris ID) if given, else the default account.
    public static func resolve(name: String?, settings: [String: String]) throws -> Account {
        try account(named: try chosenAccountName(name, in: settings), in: settings)
    }

    /// What `iris auth login` needs for the account `name` (from `--account`)
    /// or the default account. Unlike `resolve`, it needs no host and no
    /// refresh token: the sign-in gets the refresh token.
    public static func resolveGoogleSignIn(name: String?, settings: [String: String]) throws -> GoogleSignInAccount {
        let name = try chosenAccountName(name, in: settings)
        return GoogleSignInAccount(
            name: name,
            username: try value(.username, account: name, in: settings),
            client: try googleClient(forAccount: name, in: settings)
        )
    }

    /// Saves the refresh token from `iris auth login` as
    /// `IRIS_<NAME>_GOOGLE_REFRESH_TOKEN` in the `.env` file that sets the
    /// account's `IRIS_<NAME>_GOOGLE_CLIENT_ID` (the nearest one, from
    /// `directory` up). It writes nothing when no `.env` sets the client ID,
    /// because it comes from the environment. When it writes nothing, or the
    /// write fails, the result shows the line, so the user can save it.
    public static func saveGoogleRefreshToken(
        _ refreshToken: String,
        account name: String,
        startingIn directory: URL? = nil
    ) -> RefreshTokenSave {
        func save(_ outcome: RefreshTokenSave.Outcome) -> RefreshTokenSave {
            RefreshTokenSave(account: name, refreshToken: refreshToken, outcome: outcome)
        }
        guard let fileURL = DotEnv.fileURL(settingKey: key(.googleClientID, account: name), startingIn: directory) else {
            return save(.clientIDInEnvironment)
        }
        do {
            try DotEnv.setValue(refreshToken, forKey: key(.googleRefreshToken, account: name), in: fileURL)
            return save(.saved(fileURL))
        } catch {
            return save(.writeFailed(fileURL, reason: error.localizedDescription))
        }
    }

    /// The lowercased name of the account a command uses: `name` if given,
    /// else the default account. It throws when that account is not configured.
    static func chosenAccountName(_ name: String?, in settings: [String: String]) throws -> String {
        let available = accountNames(in: settings)
        guard !available.isEmpty else {
            throw IrisError.noAccountsConfigured
        }
        if let name {
            guard available.contains(name.lowercased()) else {
                throw IrisError.unknownAccount(name: name, available: available)
            }
            return name.lowercased()
        }
        guard let fallback = defaultAccountName(in: settings) else {
            throw IrisError.accountNotChosen(available: available)
        }
        if let error = defaultAccountError(in: settings) {
            throw error
        }
        return fallback
    }

    /// The error that commands without `--account` throw when `IRIS_DEFAULT_ACCOUNT`
    /// names an account that is not configured, such as a typo. Nil when the key
    /// is not set, when it names a configured account, or when no account is configured.
    public static func defaultAccountError(in settings: [String: String]) -> IrisError? {
        let available = accountNames(in: settings)
        guard let name = settings[defaultAccountKey]?.lowercased(),
              !available.isEmpty, !available.contains(name) else {
            return nil
        }
        return .invalidSetting(
            key: defaultAccountKey,
            reason: "there is no account named \"\(name)\". Configured accounts: \(available.joined(separator: ", "))."
        )
    }

    /// One summary per configured account, for `iris accounts`. It throws
    /// `noAccountsConfigured` when there is no account. A problem with one
    /// account goes in its summary, so it does not hide the others.
    public static func summaries(in settings: [String: String]) throws -> [AccountSummary] {
        let names = accountNames(in: settings)
        guard !names.isEmpty else {
            throw IrisError.noAccountsConfigured
        }
        let defaultName = defaultAccountName(in: settings)
        return names.map { name in
            let google = usesGoogle(account: name, in: settings)
            let requiredFields: [Field] = google ? [.host, .username, .googleClientSecret] : [.host, .username, .password]
            var problems = requiredFields
                .map { key($0, account: name) }
                .filter { settings[$0] == nil }
                .map { "missing \($0)" }
            if google {
                if settings[key(.password, account: name)] != nil {
                    problems.append(
                        "set \(key(.password, account: name)) or \(key(.googleClientID, account: name)), not both"
                    )
                }
                if settings[key(.googleRefreshToken, account: name)] == nil {
                    problems.append("not signed in: run `iris auth login --account \(MessagePage.shellQuoted(name))`")
                }
            }
            var port: Int?
            do {
                port = try self.port(forAccount: name, in: settings)
            } catch {
                problems.append("\(key(.port, account: name)) is not a port number")
            }
            return AccountSummary(
                name: name,
                isDefault: name == defaultName,
                username: settings[key(.username, account: name)],
                host: settings[key(.host, account: name)],
                port: port,
                problems: problems
            )
        }
    }

    /// `IRIS_MY_GMAIL_IMAP_HOST` gives `my_gmail`. Nil for a key that is not an account setting.
    static func accountName(fromKey key: String) -> String? {
        guard key.hasPrefix(keyPrefix) else { return nil }
        for field in Field.allCases {
            let suffix = "_" + field.rawValue
            guard key.hasSuffix(suffix), key.count > keyPrefix.count + suffix.count else { continue }
            let name = key.dropFirst(keyPrefix.count).dropLast(suffix.count)
            return isValidName(name) ? name.lowercased() : nil
        }
        return nil
    }

    static func isValidName<S: StringProtocol>(_ name: S) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_"
        }
    }

    static func account(named name: String, in settings: [String: String]) throws -> Account {
        Account(
            name: name,
            host: try value(.host, account: name, in: settings),
            port: try port(forAccount: name, in: settings),
            username: try value(.username, account: name, in: settings),
            authentication: try authentication(forAccount: name, in: settings)
        )
    }

    /// A password, or a Google client and refresh token when the account has
    /// `IRIS_<NAME>_GOOGLE_CLIENT_ID`. A Google account without a refresh token
    /// has not signed in yet, which `googleNotSignedIn` explains.
    static func authentication(forAccount name: String, in settings: [String: String]) throws -> Account.Authentication {
        guard usesGoogle(account: name, in: settings) else {
            return .password(try value(.password, account: name, in: settings))
        }
        let client = try googleClient(forAccount: name, in: settings)
        guard let refreshToken = settings[key(.googleRefreshToken, account: name)] else {
            throw IrisError.googleNotSignedIn(account: name)
        }
        return .google(client, refreshToken: refreshToken)
    }

    /// The account's Google client. It throws when a key is missing, and when
    /// the account also has a password, because then it is not clear which
    /// sign-in the user wants.
    static func googleClient(forAccount name: String, in settings: [String: String]) throws -> GoogleClient {
        let clientID = try value(.googleClientID, account: name, in: settings)
        let passwordKey = key(.password, account: name)
        if settings[passwordKey] != nil {
            throw IrisError.invalidSetting(
                key: passwordKey,
                reason: "the account also has \(key(.googleClientID, account: name)), so it would sign in with "
                    + "Google. Use one or the other: remove \(passwordKey) to sign in with Google, or remove the "
                    + "\(keyPrefix)\(name.uppercased())_GOOGLE_* keys to log in with the password."
            )
        }
        return GoogleClient(clientID: clientID, clientSecret: try value(.googleClientSecret, account: name, in: settings))
    }

    /// Whether the account signs in with Google: it has `IRIS_<NAME>_GOOGLE_CLIENT_ID`.
    static func usesGoogle(account name: String, in settings: [String: String]) -> Bool {
        settings[key(.googleClientID, account: name)] != nil
    }

    /// The value of a key that the account must have.
    private static func value(_ field: Field, account name: String, in settings: [String: String]) throws -> String {
        let key = key(field, account: name)
        guard let value = settings[key] else {
            throw IrisError.missingSetting(key: key)
        }
        return value
    }

    static func port(forAccount name: String, in settings: [String: String]) throws -> Int {
        let key = key(.port, account: name)
        guard let raw = settings[key] else {
            return defaultPort
        }
        guard let port = Int(raw), (1...65535).contains(port) else {
            throw IrisError.invalidSetting(key: key, reason: "\"\(raw)\" is not a port number from 1 to 65535.")
        }
        return port
    }
}
