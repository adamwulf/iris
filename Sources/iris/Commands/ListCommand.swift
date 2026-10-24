import ArgumentParser
import Foundation
import IrisKit

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the messages in a mailbox, newest first, one page at a time. Messages are not marked as read."
    )

    @OptionGroup var accountOptions: AccountOptions

    @Option(help: "The mailbox to list. Run `iris mailboxes` to see the names.")
    var mailbox: String = MailReader.defaultMailbox

    @Option(help: "The page to show. Page 1 has the newest messages.")
    var page: Int = 1

    @Option(help: "The number of messages on a page.")
    var limit: Int = MailReader.defaultPageLimit

    @Option(help: "The output format: table, json, jsonl, or id.")
    var format: OutputFormat = .table

    func run() async throws {
        let reader = MailReader(account: try accountOptions.resolve())
        let result = try await reader.list(mailbox: mailbox, page: page, limit: limit)
        CLI.printRows(try OutputFormatter.render(result.messages, format: format))
        // On stderr for every format: a JSON reader, such as an agent, also
        // needs to know that a next page exists.
        CLI.printToStderr(result.hint(account: accountOptions.account))
    }
}
