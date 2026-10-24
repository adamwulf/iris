import ArgumentParser
import Foundation
import IrisKit

enum CLI {
    /// Library log lines go to stderr, so stdout stays clean for piping.
    static func installLogHandler() {
        IrisLog.handler = { message in
            FileHandle.standardError.write(Data("iris: \(message)\n".utf8))
        }
    }
}

/// The `--account` option that every command which talks to a server takes.
struct AccountOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "The account to use, by name. Omit to use the default account (run `iris accounts` to see them).")
    var account: String?

    /// Reads the settings once and picks the account.
    func resolve() throws -> Account {
        try AccountResolver.resolve(name: account, settings: AccountResolver.settings())
    }
}
