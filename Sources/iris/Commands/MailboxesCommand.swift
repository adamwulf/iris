import ArgumentParser
import Foundation
import IrisKit

struct Mailboxes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: #"List the mailboxes (folders) with their special-use attributes, such as \Drafts and \Sent."#
    )

    @OptionGroup var accountOptions: AccountOptions

    @Option(help: "The output format.")
    var format: OutputFormat = .table

    func run() async throws {
        let reader = MailReader(account: try accountOptions.resolve())
        CLI.printRows(try OutputFormatter.render(try await reader.mailboxes(), format: format))
    }
}
