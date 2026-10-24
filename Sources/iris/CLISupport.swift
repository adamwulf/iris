import ArgumentParser
import Foundation
import IrisKit
import Logging

enum CLI {
    /// Library log lines go to stderr, so stdout stays clean for piping.
    static func installLogHandler() {
        IrisLog.handler = { message in
            FileHandle.standardError.write(Data("iris: \(message)\n".utf8))
        }
    }

    /// SwiftMail logs through swift-log, whose default handler writes `.info`
    /// lines on every connect. Keep only warnings and errors, on stderr.
    static func bootstrapSwiftLog() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .warning
            return handler
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
