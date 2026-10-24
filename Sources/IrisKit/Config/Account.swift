import Foundation

/// The settings that iris needs to log in to one IMAP account.
public struct Account: Sendable, Equatable {
    /// The account's name, lowercased: `IRIS_WORK_IMAP_HOST` belongs to the account `work`.
    public let name: String
    public let host: String
    public let port: Int
    public let username: String
    public let password: String

    public init(name: String, host: String, port: Int, username: String, password: String) {
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }
}

/// What `iris accounts` shows for one account. It never holds the password.
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
