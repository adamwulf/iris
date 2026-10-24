import ArgumentParser
import Foundation
import IrisKit

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show one message in full, as Markdown. The message is not marked as read."
    )

    @OptionGroup var accountOptions: AccountOptions

    @Argument(help: "The UID of the message, from `iris list`.")
    var uid: UInt32

    @Option(help: "The mailbox that holds the message. UIDs belong to one mailbox.")
    var mailbox: String = MailReader.defaultMailbox

    @Option(help: "The part to show: auto (HTML as Markdown when there is one, else plain text), text, or html.")
    var body: BodyPreference = .auto

    @Option(help: "The output format: markdown, json, or raw (the message source, as an .eml file).")
    var format: MessageOutputFormat = .markdown

    func run() async throws {
        let reader = MailReader(account: try accountOptions.resolve())
        let data = try await reader.rawMessage(uid: uid, mailbox: mailbox)
        FileHandle.standardOutput.write(try await MessageFormatter.render(rawMessage: data, format: format, body: body))
    }
}
