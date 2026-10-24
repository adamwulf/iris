import ArgumentParser
import Foundation
import IrisKit

struct Check: ReadOnlyCommand {
    static let configuration = CommandConfiguration(
        abstract: "Log in and show the server's capabilities and the INBOX message count, to test an account's settings."
    )

    @OptionGroup var accountOptions: AccountOptions

    func run() async throws {
        let reader = MailReader(account: try accountOptions.resolve())
        print(try await reader.check().report)
    }
}
