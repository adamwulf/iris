import Foundation

/// Where `iris auth login` put the refresh token, and what it tells the user.
/// The CLI prints `stdoutLine` (when there is one) on stdout and `message`
/// on stderr, unchanged.
public struct RefreshTokenSave: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// Written into this `.env` file.
        case saved(URL)
        /// Not written: no `.env` file sets the client ID, so it comes from the environment.
        case clientIDInEnvironment
        /// Not written: writing this `.env` file failed.
        case writeFailed(URL, reason: String)
    }

    /// The account's name, lowercased.
    public let account: String
    public let outcome: Outcome
    private let refreshToken: String

    init(account: String, refreshToken: String, outcome: Outcome) {
        self.account = account
        self.refreshToken = refreshToken
        self.outcome = outcome
    }

    /// `IRIS_<NAME>_GOOGLE_REFRESH_TOKEN=<token>` when the token was not
    /// written, so the user can save it; nil when it was. The only place
    /// iris shows a secret.
    public var stdoutLine: String? {
        if case .saved = outcome {
            return nil
        }
        return "\(key)=\(refreshToken)"
    }

    /// What stderr says: where the token went, and what to run next.
    public var message: String {
        let check = "Run `iris check --account \(MessagePage.shellQuoted(account))` to test the account."
        let saveByHand = "Save the line \(key)=... that iris printed where you keep the other keys of the account. "
        switch outcome {
        case .saved(let file):
            return "Signed in. Saved \(key) in \(file.path).\n" + check
        case .clientIDInEnvironment:
            return "Signed in. \(AccountResolver.key(.googleClientID, account: account)) is not in a .env file "
                + "(it comes from the environment), so iris wrote no file. " + saveByHand + check
        case .writeFailed(let file, let reason):
            return "Signed in, but iris could not write \(key) to \(file.path): \(reason). " + saveByHand + check
        }
    }

    private var key: String {
        AccountResolver.key(.googleRefreshToken, account: account)
    }
}
