import ArgumentParser
import Foundation
import IrisKit

@main
struct Iris: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iris",
        abstract: "A command-line tool for reading email over IMAP, and saving replies as drafts.",
        version: "0.1.0",
        // Every read-only command is here and under `iris ro`. A write command,
        // or the full form of a group with both kinds (`auth`), goes only here,
        // after them, never in `ReadOnly.commands`. `download` is a write
        // command (-o writes a file); `iris ro download` is `ReadOnlyDownload`.
        subcommands: ReadOnly.sharedCommands.map { $0 as any ParsableCommand.Type }
            + [Read.self, Unread.self, Draft.self, Download.self, Auth.self, ReadOnly.self]
    )

    static func main() async {
        CLI.bootstrapSwiftLog()
        var logging: IrisFileLog?
        var commandName = "iris"
        do {
            var command = try parseAsRoot()
            logging = IrisFileLog.openIfPossible(
                command: command, arguments: Array(CommandLine.arguments.dropFirst())
            )
            CLI.installLogHandler(fileLog: logging)
            commandName = type(of: command).configuration.commandName ?? String(describing: type(of: command))
            logging?.notice("Starting \(commandName).")
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            logging?.notice("Completed \(commandName).")
            await logging?.drain()
        } catch {
            logging?.failure(error, command: commandName)
            await logging?.drain()
            exit(withError: error)
        }
    }
}

// The library cannot import ArgumentParser, so the CLI adds the conformances.
extension OutputFormat: ExpressibleByArgument {}
extension MessageOutputFormat: ExpressibleByArgument {}
extension ThreadOutputFormat: ExpressibleByArgument {}
extension BodyPreference: ExpressibleByArgument {}
