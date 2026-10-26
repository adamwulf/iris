import ArgumentParser
import Foundation
import IrisKit
import Logging

enum CLI {
    /// Run one parsed command, draining diagnostics before returning or
    /// rethrowing to main's exit(withError:). Tests pass a temporary directory
    /// so they exercise the same lifecycle without real accounts.
    static func run(
        _ parsedCommand: any ParsableCommand,
        arguments: [String],
        logDirectory: URL = IrisFileLog.defaultDirectory
    ) async throws {
        var command = parsedCommand
        let logging = IrisFileLog.openIfPossible(
            command: command, arguments: arguments, directory: logDirectory
        )
        installLogHandler(fileLog: logging)
        logging?.record(.started, command: type(of: command))
        do {
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            logging?.record(.completed, command: type(of: command))
            await logging?.drain()
        } catch {
            if let exitCode = error as? ExitCode {
                logging?.record(.exited(exitCode.rawValue), command: type(of: command))
            } else {
                logging?.record(.failed(error), command: type(of: command))
            }
            await logging?.drain()
            throw error
        }
    }

    /// Derive names from the parser's command tree, never from argv values.
    /// Top-level paths come first; the duplicate read-only paths do not log.
    static func commandPath(for command: any ParsableCommand.Type) -> String {
        func path(under node: any ParsableCommand.Type) -> [String]? {
            if node == command { return [node._commandName] }
            for child in node.configuration.subcommands {
                if let remainder = path(under: child) {
                    return [node._commandName] + remainder
                }
            }
            return nil
        }
        return path(under: Iris.self)?.dropFirst().joined(separator: " ") ?? command._commandName
    }

    /// Live lines go to stderr; fixed behavior events go to the optional file
    /// sink. Neither destination mixes diagnostics with stdout data.
    static func installLogHandler(fileLog: IrisFileLog?) {
        IrisLog.handler = { message in
            printToStderr("iris: \(message)")
        }
        IrisLog.fileHandler = { record in
            fileLog?.record(record.event, file: record.file, function: record.function, line: record.line)
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

    /// Opens `url` in the default browser. A failure is not reported: the
    /// sign-in also logs the URL, so the user can open it by hand.
    @Sendable static func openInBrowser(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
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
/// A command that takes an iris ID (such as `show` and `download`) has none.
/// A command that takes an iris ID uses the account that the ID names.
struct AccountOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "The account to use, by name. Omit to use the default account (run `iris accounts` to see them).")
    var account: String?

    /// Reads the settings once and picks the account.
    func resolve() throws -> Account {
        try AccountResolver.resolve(name: account, settings: AccountResolver.settings())
    }
}
