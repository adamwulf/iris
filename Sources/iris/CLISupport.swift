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

    /// Writes a list command's rendered rows to stdout. Zero rows as `id` or
    /// `jsonl` render as empty text, which writes nothing, so a
    /// `while read` loop over the output gets no empty line.
    static func printRows(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        print(text)
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
