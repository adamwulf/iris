import ArgumentParser
import Foundation
import IrisKit

struct Accounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the configured email accounts. Passwords are never shown."
    )

    @Option(help: "The output format.")
    var format: OutputFormat = .listDefault

    func run() async throws {
        let settings = AccountResolver.settings()
        CLI.printRows(try OutputFormatter.render(try AccountResolver.summaries(in: settings), format: format))
        // A bad default marks no row as the default and makes every command
        // without --account fail, so say why.
        if let error = AccountResolver.defaultAccountError(in: settings) {
            CLI.printToStderr("Warning: \(error.localizedDescription)")
        }
    }
}
