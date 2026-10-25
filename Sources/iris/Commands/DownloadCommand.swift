import ArgumentParser
import Foundation
import IrisKit

/// `iris download`: a write command, so it is never under `iris ro`. With
/// `-o` it writes a file whose content and name come from the sender.
/// `iris ro download` is `ReadOnlyDownload`, the same command without `-o`.
/// Both take `DownloadArguments` and run its `run(outputPath:)`, so they cannot drift.
struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download one attachment of a message: save it with -o, or write its bytes to stdout. The message is not marked as read.",
        discussion: "The attachment ID is the number that `iris show` and `iris thread` list first on each attachment line. Without -o, the bytes go to stdout, which must not be a terminal: redirect it to a file. With -o, iris saves a new file at that path, or in that folder under the attachment's filename made safe, prints the saved path, and never overwrites a file. A download that takes more than 60 seconds fails."
    )

    @OptionGroup var arguments: DownloadArguments

    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "Save the attachment in this new file, or in this folder under its filename. Omit to write the bytes to stdout.",
            valueName: "path"
        )
    )
    var output: String?

    func run() async throws {
        try await arguments.run(outputPath: output)
    }
}

/// `iris ro download`: `Download` without `-o`, so it is read-only. Under
/// `ro`, iris writes nothing to disk itself: the bytes go to stdout, so any
/// file write is done by the caller's shell, inside the agent's sandbox and
/// permission rules, never by iris at a path the sandbox does not cover.
struct ReadOnlyDownload: ReadOnlyCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Write the bytes of one attachment of a message to stdout. The message is not marked as read.",
        discussion: "The attachment ID is the number that `iris show` and `iris thread` list first on each attachment line. stdout must not be a terminal: redirect it to a file. Under `iris ro` there is no -o, so iris itself writes no file. A download that takes more than 60 seconds fails."
    )

    @OptionGroup var arguments: DownloadArguments

    func run() async throws {
        try await arguments.run(outputPath: nil)
    }
}

/// The arguments of `iris download` and `iris ro download`, and the run they share.
struct DownloadArguments: ParsableArguments {
    // The iris ID names the account, so `download` has no --account.
    @Argument(help: .irisID, transform: IrisID.init(parsing:))
    var irisID: IrisID

    @Argument(
        help: "The attachment ID that `iris show` lists first on each attachment line, such as 2 or 1.2.",
        transform: AttachmentID.init(parsing:)
    )
    var attachmentID: AttachmentID

    /// Downloads the attachment, then writes its bytes to stdout, or, with
    /// `outputPath` (`-o`), saves it and writes the saved path.
    func run(outputPath: String?) async throws {
        // Before the download, so a terminal on stdout fails before iris connects.
        let output = try AttachmentOutput(path: outputPath, stdoutIsTerminal: isatty(STDOUT_FILENO) == 1)
        let account = try AccountResolver.resolve(name: irisID.account, settings: AccountResolver.settings())
        let attachment = try await MailReader(account: account).attachment(attachmentID, of: irisID)
        FileHandle.standardOutput.write(try output.write(attachment))
    }
}
