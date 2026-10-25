import ArgumentParser
import IrisKit

/// A write command: it sets the `\Seen` flag, so it is never under `iris ro`.
struct Read: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mark one message as read. A message that is already read stays read."
    )

    // The iris ID names the account and the mailbox, so `read` has no --account or --mailbox.
    @Argument(help: .irisID, transform: IrisID.init(parsing:))
    var irisID: IrisID

    func run() async throws {
        let account = try AccountResolver.resolve(name: irisID.account, settings: AccountResolver.settings())
        try await MailWriter(account: account).markRead(irisID)
    }
}
