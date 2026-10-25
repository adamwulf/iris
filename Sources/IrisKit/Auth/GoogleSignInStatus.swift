import Foundation

/// What `iris auth status` shows for one account: which Google keys are set
/// (never their values), and whether Google gives an access token for the
/// refresh token now. It never holds a secret.
public struct GoogleSignInStatus: Sendable, Equatable, Encodable {
    public let name: String
    public let username: String?
    public let clientIDSet: Bool
    public let clientSecretSet: Bool
    public let refreshTokenSet: Bool
    /// Whether the token refresh worked.
    public let signedIn: Bool
    /// Why the account is not signed in, such as an expired sign-in. Nil when `signedIn`.
    public let problem: String?

    public init(
        name: String,
        username: String?,
        clientIDSet: Bool,
        clientSecretSet: Bool,
        refreshTokenSet: Bool,
        problem: String?
    ) {
        self.name = name
        self.username = username
        self.clientIDSet = clientIDSet
        self.clientSecretSet = clientSecretSet
        self.refreshTokenSet = refreshTokenSet
        self.signedIn = problem == nil
        self.problem = problem
    }

    /// The status of the account `name` (from `--account`), or of every
    /// account that signs in with Google when `name` is nil. It refreshes one
    /// token per account that has the keys, and opens no IMAP connection. A
    /// problem with one account goes in its row, so it does not hide the others.
    public static func check(account name: String?, settings: [String: String]) async throws -> [GoogleSignInStatus] {
        try await check(account: name, settings: settings, transport: URLSessionTransport())
    }

    /// The same over `transport`. Tests pass a stub.
    static func check(
        account name: String?,
        settings: [String: String],
        transport: any HTTPTransport
    ) async throws -> [GoogleSignInStatus] {
        let names: [String]
        if let name {
            names = [try AccountResolver.chosenAccountName(name, in: settings)]
        } else {
            guard !AccountResolver.accountNames(in: settings).isEmpty else {
                throw IrisError.noAccountsConfigured
            }
            names = AccountResolver.accountNames(in: settings).filter {
                AccountResolver.usesGoogle(account: $0, in: settings)
            }
            guard !names.isEmpty else {
                throw IrisError.noGoogleAccounts
            }
        }
        let endpoint = GoogleTokenEndpoint(transport: transport)
        var statuses: [GoogleSignInStatus] = []
        for name in names {
            statuses.append(await status(of: name, settings: settings, endpoint: endpoint))
        }
        return statuses
    }

    private static func status(
        of name: String,
        settings: [String: String],
        endpoint: GoogleTokenEndpoint
    ) async -> GoogleSignInStatus {
        func isSet(_ field: AccountResolver.Field) -> Bool {
            settings[AccountResolver.key(field, account: name)] != nil
        }
        let problem: String?
        if !AccountResolver.usesGoogle(account: name, in: settings) {
            problem = "\(AccountResolver.key(.googleClientID, account: name)) is not set, "
                + "so the account logs in with a password, not with Google"
        } else {
            do {
                if case .google(let client, let refreshToken) = try AccountResolver.authentication(
                    forAccount: name, in: settings
                ) {
                    _ = try await endpoint.accessToken(client: client, refreshToken: refreshToken, account: name)
                }
                problem = nil
            } catch {
                // The token endpoint's errors are redacted already; this also covers any other text.
                let secrets = [AccountResolver.Field.password, .googleClientSecret, .googleRefreshToken]
                    .compactMap { settings[AccountResolver.key($0, account: name)] }
                let text = (error as? IrisError)?.errorDescription ?? String(describing: error)
                problem = Redaction.redacting(secrets, in: text)
            }
        }
        return GoogleSignInStatus(
            name: name,
            username: settings[AccountResolver.key(.username, account: name)],
            clientIDSet: isSet(.googleClientID),
            clientSecretSet: isSet(.googleClientSecret),
            refreshTokenSet: isSet(.googleRefreshToken),
            problem: problem
        )
    }
}

extension GoogleSignInStatus: IrisRow {
    public static var tableColumns: [String] {
        ["NAME", "USERNAME", "CLIENT ID", "CLIENT SECRET", "REFRESH TOKEN", "STATUS"]
    }

    public var tableValues: [String] {
        func word(_ isSet: Bool) -> String { isSet ? "set" : "missing" }
        return [
            name,
            username ?? "",
            word(clientIDSet),
            word(clientSecretSet),
            word(refreshTokenSet),
            problem ?? "ok",
        ]
    }

    public var idValue: String { name }
}
