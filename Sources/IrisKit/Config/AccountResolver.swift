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
/// A name is uppercase letters, digits, and underscores in the key, and it may
/// contain underscores because the suffix (`_IMAP_HOST`, ...) is fixed. Users
/// type the name in any case; iris shows it lowercased.
public enum AccountResolver {
    public enum Field: String, CaseIterable, Sendable {
        case host = "IMAP_HOST"
        case port = "IMAP_PORT"
        case username = "IMAP_USERNAME"
        case password = "IMAP_PASSWORD"
    }

    public static let keyPrefix = "IRIS_"
    public static let defaultAccountKey = "IRIS_DEFAULT_ACCOUNT"
    public static let defaultPort = 993

    private static let requiredFields: [Field] = [.host, .username, .password]

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

    /// The lowercased names of every account that has at least one `IRIS_<NAME>_IMAP_*` key, sorted.
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

    /// The account a command uses: `name` (from `--account`) if given, else the default account.
    public static func resolve(name: String?, settings: [String: String]) throws -> Account {
        let available = accountNames(in: settings)
        guard !available.isEmpty else {
            throw IrisError.noAccountsConfigured
        }
        if let name {
            guard available.contains(name.lowercased()) else {
                throw IrisError.unknownAccount(name: name, available: available)
            }
            return try account(named: name.lowercased(), in: settings)
        }
        guard let fallback = defaultAccountName(in: settings) else {
            throw IrisError.accountNotChosen(available: available)
        }
        if let error = defaultAccountError(in: settings) {
            throw error
        }
        return try account(named: fallback, in: settings)
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
            var problems = requiredFields
                .map { key($0, account: name) }
                .filter { settings[$0] == nil }
                .map { "missing \($0)" }
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
        func required(_ field: Field) throws -> String {
            let key = key(field, account: name)
            guard let value = settings[key] else {
                throw IrisError.missingSetting(key: key)
            }
            return value
        }
        return Account(
            name: name,
            host: try required(.host),
            port: try port(forAccount: name, in: settings),
            username: try required(.username),
            password: try required(.password)
        )
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
