import ArgumentParser
import Foundation
import IrisKit

struct List: ReadOnlyCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the messages in a mailbox, newest first, one page at a time. Messages are not marked as read.",
        discussion: "The filter options (--unread, --flagged, --from, --subject, --since, --before) combine: a message must match all of them. The server does the matching."
    )

    @OptionGroup var accountOptions: AccountOptions

    @Option(help: "The mailbox to list. Run `iris mailboxes` to see the names.")
    var mailbox: String = MailReader.defaultMailbox

    @Flag(help: "Show only unread messages.")
    var unread = false

    @Flag(help: "Show only flagged messages (starred, in Gmail).")
    var flagged = false

    @Option(help: ArgumentHelp(
        "Show only messages whose From header has this text, in the name or the address.", valueName: "text"
    ))
    var from: String?

    @Option(help: ArgumentHelp("Show only messages whose subject has this text.", valueName: "text"))
    var subject: String?

    @Option(
        help: ArgumentHelp("Show only messages that the server received on this day or later.", valueName: "YYYY-MM-DD"),
        transform: CalendarDay.init(parsing:)
    )
    var since: CalendarDay?

    @Option(
        help: ArgumentHelp("Show only messages that the server received before this day.", valueName: "YYYY-MM-DD"),
        transform: CalendarDay.init(parsing:)
    )
    var before: CalendarDay?

    @Option(help: "The page to show. Page 1 has the newest messages.")
    var page: Int = 1

    @Option(help: "The number of messages on a page.")
    var limit: Int = MailReader.defaultPageLimit

    @Option(help: "The output format.")
    var format: OutputFormat = .listDefault

    var filter: MessageFilter {
        MessageFilter(unread: unread, flagged: flagged, from: from, subject: subject, since: since, before: before)
    }

    func run() async throws {
        let reader = MailReader(account: try accountOptions.resolve())
        let result = try await reader.list(mailbox: mailbox, filter: filter, page: page, limit: limit)
        CLI.printRows(try OutputFormatter.render(result.messages, format: format))
        // On stderr for every format: a JSON reader, such as an agent, also
        // needs to know that a next page exists.
        CLI.printToStderr(result.hint(account: accountOptions.account, format: format))
    }
}
