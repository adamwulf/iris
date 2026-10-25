import Foundation

/// The settings that iris needs to log in to one IMAP account.
public struct Account: Sendable, Equatable {
    /// How iris proves who it is to the IMAP server.
    public enum Authentication: Sendable, Equatable {
        /// LOGIN with the username and this password, usually an app-specific password.
        case password(String)
        /// AUTHENTICATE XOAUTH2 with an access token that iris gets from Google
        /// with this client and refresh token before each session.
        case google(GoogleClient, refreshToken: String)
    }

    /// The account's name, lowercased: `IRIS_WORK_IMAP_HOST` belongs to the account `work`.
    public let name: String
    public let host: String
    public let port: Int
    /// For a Google account, the address chosen at Google sign-in.
    public let username: String
    public let authentication: Authentication

    public init(name: String, host: String, port: Int, username: String, authentication: Authentication) {
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authentication = authentication
    }

    /// Every secret the account holds. No error message, log line, or JSON output may show one.
    public var secrets: [String] {
        switch authentication {
        case .password(let password):
            return [password]
        case .google(let client, let refreshToken):
            return [client.clientSecret, refreshToken]
        }
    }
}

/// A Google Cloud OAuth client of type "Desktop app". The client ID is not a
/// secret (it is in the sign-in URL), but the client secret is.
public struct GoogleClient: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

/// What `iris auth login` needs to sign in to Google for one account. An
/// account has this before its first sign-in, when it has no refresh token yet.
public struct GoogleSignInAccount: Sendable, Equatable {
    /// The account's name, lowercased.
    public let name: String
    /// The address to sign in as: the sign-in page suggests it.
    public let username: String
    public let client: GoogleClient

    public init(name: String, username: String, client: GoogleClient) {
        self.name = name
        self.username = username
        self.client = client
    }
}

/// What `iris accounts` shows for one account. It never holds a secret.
public struct AccountSummary: Sendable, Equatable, Encodable {
    public let name: String
    public let isDefault: Bool
    public let username: String?
    public let host: String?
    public let port: Int?
    /// What stops the account from working, such as a missing key. Empty when the account is ready.
    public let problems: [String]

    public init(name: String, isDefault: Bool, username: String?, host: String?, port: Int?, problems: [String]) {
        self.name = name
        self.isDefault = isDefault
        self.username = username
        self.host = host
        self.port = port
        self.problems = problems
    }
}

extension AccountSummary: IrisRow {
    public static var tableColumns: [String] { ["NAME", "DEFAULT", "USERNAME", "SERVER", "STATUS"] }

    public var tableValues: [String] {
        let server = host.map { "\($0):\(port.map(String.init) ?? "?")" } ?? ""
        let status = problems.isEmpty ? "ok" : problems.joined(separator: "; ")
        return [name, isDefault ? "yes" : "", username ?? "", server, status]
    }

    public var idValue: String { name }
}
