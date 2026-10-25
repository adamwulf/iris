import ArgumentParser
import Foundation
import IrisKit

/// `iris auth`: Google sign-in. A group with both kinds: `login` opens the
/// browser and writes `.env`, and `status` only reads, so `iris ro auth` is
/// `ReadOnlyAuth`, which has only `status`.
struct Auth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sign in to Google, for an account that uses Google OAuth instead of a password.",
        subcommands: [Login.self, Status.self]
    )

    struct Status: ReadOnlyCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show which Google keys each account has, and test a token refresh. Values are never shown.",
            discussion: "Without --account, it checks every account that has IRIS_<NAME>_GOOGLE_CLIENT_ID. It gets one access token from Google per account and logs in to no mail server. It exits with status 1 when an account is not signed in."
        )

        @Option(name: .shortAndLong, help: "The account to check, by name. Omit to check every account that signs in with Google.")
        var account: String?

        @Option(help: "The output format.")
        var format: OutputFormat = .listDefault

        func run() async throws {
            let statuses = try await GoogleSignInStatus.check(account: account, settings: AccountResolver.settings())
            CLI.printRows(try OutputFormatter.render(statuses, format: format))
            if !statuses.allSatisfy(\.signedIn) {
                throw ExitCode.failure
            }
        }
    }

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

/// `iris ro auth`: the read-only children of `auth`, the same leaf types, so
/// `iris ro auth status` works and `iris ro auth login` fails to parse.
struct ReadOnlyAuth: ReadOnlyCommand {
    static let children: [any ReadOnlyCommand.Type] = [Auth.Status.self]

    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Check the Google sign-in of the accounts that use Google OAuth.",
        subcommands: children.map { $0 as any ParsableCommand.Type }
    )
}
