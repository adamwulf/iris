import ArgumentParser
import Foundation
import IrisKit

/// Both children save drafts, so neither belongs under `iris ro`.
struct Draft: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create reply drafts or update saved drafts. iris never sends mail.",
        subcommands: [Reply.self, Update.self]
    )

    private static func printSavedDraft(_ saved: SavedDraft) {
        if let draftID = saved.irisID {
            FileHandle.standardOutput.write(Data("\(draftID)\n".utf8))
        } else if let note = saved.missingIDNote {
            CLI.printToStderr(note)
        }
    }
}

extension Draft {
    struct Reply: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Save a reply to a message as a draft. iris never sends mail: review and send the draft in your mail app.",
            discussion: "The reply is Markdown, from exactly one source: the argument, -F <path>, or stdin. The draft has the Markdown as plain text and as HTML, with the original quoted below it, and goes to the \\Drafts mailbox. Each --attach <path> attaches one file; iris reads every file before it connects. iris prints the draft's iris ID. The From address is IRIS_<NAME>_FROM, else the username when it is an address."
        )

        // The iris ID names the account, so `draft reply` has no --account.
        @Argument(help: .irisID, transform: IrisID.init(parsing:))
        var irisID: IrisID

        @Argument(help: "The reply, in Markdown. Omit it to read the reply from -F or stdin. A reply that starts with - (a Markdown list) needs -- before it, as in iris draft reply 'work/INBOX/4821' -- '- yes', or use -F or stdin.")
        var body: String?

        @Option(
            name: [.customShort("F"), .customLong("file")],
            help: ArgumentHelp("Read the reply (Markdown) from this file. -F - reads stdin.", valueName: "path")
        )
        var file: String?

        @Option(help: ArgumentHelp("Attach this file to the draft. Repeat --attach for each file.", valueName: "path"))
        var attach: [String] = []

        @Flag(help: "Reply to all: also Cc the original's To and Cc recipients, except you.")
        var all = false

        @Flag(name: .customLong("no-quote"), help: "Leave out the quoted original message.")
        var noQuote = false

        func run() async throws {
            let settings = AccountResolver.settings()
            let account = try AccountResolver.resolve(name: irisID.account, settings: settings)
            let from = try AccountResolver.fromAddress(for: account, in: settings)
            // Before the reply, so a bad path fails before a reply typed on stdin, and before login.
            let attachments = try attach.map(DraftAttachment.read(path:))
            let reply = try DraftBody.read(
                argument: body, file: file, attaching: !attach.isEmpty, stdinIsTerminal: isatty(STDIN_FILENO) == 1
            )
            let saved = try await MailWriter(account: account).saveReply(
                to: irisID, body: reply, from: from, replyAll: all, quote: !noQuote, attachments: attachments
            )
            Draft.printSavedDraft(saved)
        }
    }
}

extension Draft {
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Replace the body of a saved draft. iris never sends mail.",
            discussion: "The replacement body is Markdown, from exactly one source: the argument, -F <path>, or stdin. Recipients, subject, threading headers, and attachments are preserved. No reply quote is added. iris prints the saved draft's iris ID, which may differ from the input ID; use the printed ID for subsequent operations."
        )

        @Argument(help: .irisID, transform: IrisID.init(parsing:))
        var irisID: IrisID

        @Argument(help: "The replacement body, in Markdown. Omit it to read from -F or stdin. A body that starts with - needs -- before it, as in iris draft update 'work/Drafts/42' -- '- yes', or use -F or stdin.")
        var body: String?

        @Option(
            name: [.customShort("F"), .customLong("file")],
            help: ArgumentHelp("Read the replacement body (Markdown) from this file. -F - reads stdin.", valueName: "path")
        )
        var file: String?

        func run() async throws {
            let settings = AccountResolver.settings()
            let account = try AccountResolver.resolve(name: irisID.account, settings: settings)
            let replacement = try DraftBody.read(
                argument: body, file: file, attaching: false, stdinIsTerminal: isatty(STDIN_FILENO) == 1
            )
            let saved = try await MailWriter(account: account).updateDraft(irisID, body: replacement)
            Draft.printSavedDraft(saved)
        }
    }
}
