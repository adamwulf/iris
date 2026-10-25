import ArgumentParser
import Foundation
import IrisKit

struct Show: ReadOnlyCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show one message, as Markdown. The message is not marked as read."
    )

    // The iris ID names the account and the mailbox, so `show` has no --account or --mailbox.
    @Argument(help: .irisID, transform: IrisID.init(parsing:))
    var irisID: IrisID

    @Option(help: "The part to show. auto shows the HTML part as Markdown when there is one, else the plain text.")
    var body: BodyPreference = .auto

    @Flag(help: "Show the whole body. Without it, the quoted history (the earlier messages a reply quotes under its own text) and the signature at the end of the body are hidden, with a line that says so (json: bodyTrimmed). A forward is always shown whole. raw is always the whole message.")
    var full = false

    @Option(help: "The output format. markdown and json show the iris ID (json as irisID, next to the Message-ID header as messageID) and a message: URL that opens the message in Apple Mail (json as appleMailURL); for a message over 1 MiB they download only its text and HTML parts, and its attachments stay on the server. raw is the message source exactly as the server sent it, as an .eml file: always the whole message, so a large one can time out.")
    var format: MessageOutputFormat = .markdown

    func run() async throws {
        let account = try AccountResolver.resolve(name: irisID.account, settings: AccountResolver.settings())
        let reader = MailReader(account: account)
        if let documentFormat = format.documentFormat {
            // A large message is downloaded in parts: its body, and not its attachments.
            let message = try await reader.message(irisID)
            FileHandle.standardOutput.write(
                try await MessageFormatter.render(
                    message: message, irisID: irisID, format: documentFormat, body: body, full: full
                )
            )
        } else {
            // The source is the whole message, at any size.
            FileHandle.standardOutput.write(try await reader.rawMessage(irisID))
        }
    }
}
