import ArgumentParser
import Foundation
import IrisKit

struct Show: ReadOnlyCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show one message in full, as Markdown. The message is not marked as read."
    )

    // The iris ID names the account and the mailbox, so `show` has no --account or --mailbox.
    @Argument(help: .irisID, transform: IrisID.init(parsing:))
    var irisID: IrisID

    @Option(help: "The part to show. auto shows the HTML part as Markdown when there is one, else the plain text.")
    var body: BodyPreference = .auto

    @Option(help: "The output format. markdown and json show the iris ID (json as irisID, next to the Message-ID header as messageID) and a message: URL that opens the message in Apple Mail (json as appleMailURL). raw is the message source exactly as the server sent it, as an .eml file.")
    var format: MessageOutputFormat = .markdown

    func run() async throws {
        let account = try AccountResolver.resolve(name: irisID.account, settings: AccountResolver.settings())
        let reader = MailReader(account: account)
        if let documentFormat = format.documentFormat {
            // A large message is downloaded in parts: its body, and not its attachments.
            let message = try await reader.message(irisID)
            FileHandle.standardOutput.write(
                try await MessageFormatter.render(message: message, irisID: irisID, format: documentFormat, body: body)
            )
        } else {
            // The source is the whole message, at any size.
            FileHandle.standardOutput.write(try await reader.rawMessage(irisID))
        }
    }
}
