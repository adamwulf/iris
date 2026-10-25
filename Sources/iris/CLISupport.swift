import ArgumentParser
import Foundation
import IrisKit
import Logging

enum CLI {
    /// Library log lines go to stderr, so stdout stays clean for piping.
    static func installLogHandler() {
        IrisLog.handler = { message in
            printToStderr("iris: \(message)")
        }
    }

    /// Writes one line to stderr: hints and notes that must not mix with the data on stdout.
    static func printToStderr(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }

    /// Writes a list command's rendered rows to stdout unchanged.
    /// `OutputFormatter.render` already ends every line with a newline.
    static func printRows(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    /// SwiftMail logs through swift-log, whose default handler writes `.info`
    /// lines on every connect, and it logs every failed command at `.error`, a
    /// long diagnostic line before iris's own message. iris reports every
    /// failure itself as an `IrisError`, so keep only `.critical` lines, on stderr.
    static func bootstrapSwiftLog() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .critical
            return handler
        }
    }
}

extension ArgumentHelp {
    /// The help for an iris ID argument, the same in every command that takes one.
    static let irisID: ArgumentHelp = "The iris ID from `iris list`: <account>/<mailbox>/<UID>, for example 'work/INBOX/4821'. Put it in single quotes: a mailbox name can have spaces or [ ], which the shell would change."
}

/// The `--account` option for the commands that talk to a server and take no iris ID.
/// A command that takes an iris ID uses the account that the ID names.
struct AccountOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "The account to use, by name. Omit to use the default account (run `iris accounts` to see them).")
    var account: String?

    /// Reads the settings once and picks the account.
    func resolve() throws -> Account {
        try AccountResolver.resolve(name: account, settings: AccountResolver.settings())
    }
}
