import ArgumentParser
import Foundation
import IrisKit

struct Show: ReadOnlyCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show one message in full, as Markdown. The message is not marked as read."
    )

    // The iris ID names the account and the mailbox, so `show` has no --account or --mailbox.
    @Argument(
        help: "The iris ID from `iris list`: <account>/<mailbox>/<UID>, for example 'work/INBOX/4821'. Put it in single quotes: a mailbox name can have spaces or [ ], which the shell would change.",
        transform: IrisID.init(parsing:)
    )
    var irisID: IrisID

    @Option(help: "The part to show. auto shows the HTML part as Markdown when there is one, else the plain text.")
    var body: BodyPreference = .auto

    @Option(help: "The output format. markdown and json show the iris ID (json as irisID, next to the Message-ID header as messageID). raw is the message source exactly as the server sent it, as an .eml file.")
    var format: MessageOutputFormat = .markdown

    func run() async throws {
        let account = try AccountResolver.resolve(name: irisID.account, settings: AccountResolver.settings())
        let data = try await MailReader(account: account).rawMessage(irisID)
        FileHandle.standardOutput.write(
            try await MessageFormatter.render(rawMessage: data, irisID: irisID, format: format, body: body)
        )
    }
}
