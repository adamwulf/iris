import ArgumentParser
import IrisKit

/// A write command: it clears the `\Seen` flag, so it is never under `iris ro`.
struct Unread: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Mark one message as unread. A message that is already unread stays unread."
    )

    // The iris ID names the account and the mailbox, so `unread` has no --account or --mailbox.
    @Argument(help: .irisID, transform: IrisID.init(parsing:))
    var irisID: IrisID

    func run() async throws {
        let account = try AccountResolver.resolve(name: irisID.account, settings: AccountResolver.settings())
        try await MailWriter(account: account).markUnread(irisID)
    }
}
