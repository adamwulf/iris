import Foundation

/// The persistent log's boundary: no files under `ro`, and no configured
/// credentials in diagnostic text. Protocol payloads and command arguments
/// must never be passed to this sink in the first place.
public struct FileLogPolicy: Sendable {
    private let secrets: [String]

    public init(settings: [String: String]) {
        secrets = AccountResolver.accountNames(in: settings).flatMap { account in
            [AccountResolver.Field.password, .googleClientSecret, .googleRefreshToken]
                .compactMap { settings[AccountResolver.key($0, account: account)] }
        }
    }

    /// Arguments exclude the executable name. A leading option terminator
    /// does not turn a read-only invocation into one that can write logs.
    public static func writesFiles(arguments: [String]) -> Bool {
        arguments.drop(while: { $0 == "--" }).first != "ro"
    }

    public func redacting(_ message: String) -> String {
        Redaction.redacting(secrets, in: message)
    }

    /// Parser and arbitrary errors can repeat input, including a draft body.
    /// IrisError's network boundaries already redact transient credentials.
    public func failure(_ error: Error, command: String) -> String {
        let reason = (error as? IrisError)?.localizedDescription ?? "Command did not complete."
        return redacting("\(command): \(reason)")
    }
}
