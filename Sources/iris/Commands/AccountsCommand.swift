import ArgumentParser
import Foundation
import IrisKit

struct Accounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the configured email accounts. Passwords are never shown."
    )

    @Option(help: "The output format: table, json, jsonl, or id.")
    var format: OutputFormat = .table

    func run() async throws {
        let summaries = AccountResolver.summaries(in: AccountResolver.settings())
        guard !summaries.isEmpty else {
            throw IrisError.noAccountsConfigured
        }
        print(try OutputFormatter.render(summaries, format: format))
    }
}
