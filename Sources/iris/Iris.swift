import ArgumentParser
import Foundation
import IrisKit

@main
struct Iris: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iris",
        abstract: "A command-line tool for reading email over IMAP.",
        version: "0.1.0",
        subcommands: [Accounts.self, Check.self, Mailboxes.self, List.self, Show.self]
    )

    static func main() async {
        CLI.installLogHandler()
        CLI.bootstrapSwiftLog()
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}

// The library cannot import ArgumentParser, so the CLI adds the conformances.
extension OutputFormat: ExpressibleByArgument {}
extension MessageOutputFormat: ExpressibleByArgument {}
extension BodyPreference: ExpressibleByArgument {}
