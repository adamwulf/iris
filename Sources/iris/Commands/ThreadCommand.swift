import ArgumentParser
import Foundation
import IrisKit

// Not named `Thread`, which would clash with Foundation's `Thread`.
struct ThreadCommand: ReadOnlyCommand {
    static let configuration = CommandConfiguration(
        commandName: "thread",
        abstract: "Show every message in the thread of one message, oldest first, as Markdown or JSON, or only their iris IDs. No message is marked as read.",
        discussion: "iris searches INBOX, the Sent, Archive, Drafts, and All Mail mailboxes, and the message's own mailbox for the messages that reply to the message, or that it replies to, again and again until no new message turns up. A message with a different subject (ignoring Re:, Fwd:, Fw:, and tags such as [list]) starts a new thread and is left out. A message in several mailboxes is shown once. A message that cannot be shown is left out, with a line on stderr. When no message can be shown, the command fails as `iris show` would for the message you named. With --format id, iris finds the thread from the headers alone and downloads no message, so it saves the download time and leaves nothing out."
    )

    // The iris ID names the account and the mailbox, so `thread` has no --account or --mailbox.
    @Argument(
        help: "The iris ID of any message in the thread, from `iris list`: <account>/<mailbox>/<UID>, for example 'work/INBOX/4821'. Put it in single quotes: a mailbox name can have spaces or [ ], which the shell would change.",
        transform: IrisID.init(parsing:)
    )
    var irisID: IrisID

    @Option(help: "The part to show for each message. auto shows the HTML part as Markdown when there is one, else the plain text.")
    var body: BodyPreference = .auto

    @Option(help: "The output format. markdown shows each message as `iris show` does, with a * * * line between messages. json is an array of the objects that `iris show --format json` gives, and jsonl gives one of those objects per line. id gives only the iris ID of each message, one per line, and downloads no message.")
    var format: ThreadOutputFormat = .markdown

    func run() async throws {
        let account = try AccountResolver.resolve(name: irisID.account, settings: AccountResolver.settings())
        let reader = MailReader(account: account)
        if format == .id {
            // The walk reads only headers, so the iris IDs need no download.
            FileHandle.standardOutput.write(MessageFormatter.render(threadIDs: try await reader.threadIDs(irisID)))
        } else {
            let messages = try await reader.thread(irisID)
            FileHandle.standardOutput.write(try await MessageFormatter.render(thread: messages, format: format, body: body))
        }
    }
}
