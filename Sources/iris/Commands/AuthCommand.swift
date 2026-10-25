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

            let tokenKey = AccountResolver.key(.googleRefreshToken, account: account.name)
            let check = "iris check --account \(account.name)"
            let problem: String
            do {
                if let file = try AccountResolver.saveGoogleRefreshToken(refreshToken, account: account.name) {
                    CLI.printToStderr("Signed in. Saved \(tokenKey) in \(file.path).")
                    CLI.printToStderr("Run `\(check)` to test the account.")
                    return
                }
                problem = "\(AccountResolver.key(.googleClientID, account: account.name)) is not in a .env file "
                    + "(it comes from the environment), so iris did not write one."
            } catch {
                problem = "iris could not write \(tokenKey) to .env: \(error.localizedDescription)"
            }
            // The only place iris shows a secret: the user must save it by hand.
            print("\(tokenKey)=\(refreshToken)")
            CLI.printToStderr("Signed in. \(problem) Save the line above where you keep the other keys "
                + "of the account, then run `\(check)` to test it.")
        }
    }
}
