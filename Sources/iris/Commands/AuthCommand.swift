import ArgumentParser
import Foundation
import IrisKit

/// `iris auth`: Google sign-in. A write command: `login` opens the browser and
/// writes `.env`, so `auth` is never under `iris ro`.
struct Auth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sign in to Google, for an account that uses Google OAuth instead of a password.",
        subcommands: [Login.self]
    )

    struct Login: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Sign in to Google in the browser and save the refresh token in .env.",
            discussion: "The account needs IRIS_<NAME>_IMAP_USERNAME, IRIS_<NAME>_GOOGLE_CLIENT_ID, and IRIS_<NAME>_GOOGLE_CLIENT_SECRET. The refresh token goes in the .env file that sets the client ID, as IRIS_<NAME>_GOOGLE_REFRESH_TOKEN. A Google Cloud app in Testing mode signs you out after 7 days; then run this again."
        )

        @OptionGroup var accountOptions: AccountOptions

        func run() async throws {
            let account = try AccountResolver.resolveGoogleSignIn(
                name: accountOptions.account, settings: AccountResolver.settings()
            )
            let refreshToken = try await GoogleSignIn(account: account, openURL: CLI.openInBrowser).run()
            let save = AccountResolver.saveGoogleRefreshToken(refreshToken, account: account.name)
            // The only place iris shows a secret: a token it did not write, for the user to save.
            if let line = save.stdoutLine {
                print(line)
            }
            CLI.printToStderr(save.message)
        }
    }
}
