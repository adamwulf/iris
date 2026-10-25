import ArgumentParser

/// A command that cannot change anything on the server (no send, draft, move,
/// flag, or delete) and writes no file. Only these commands can be listed
/// under `iris ro`.
protocol ReadOnlyCommand: AsyncParsableCommand {}

/// `iris ro <command>`: the read-only commands, and nothing else.
///
/// `iris ro list` is the same command as `iris list`. The group exists so that
/// an agent can be allowed to run only `iris ro ...`: it can then read mail,
/// but a write command such as a draft is not in this group, so it cannot run.
struct ReadOnly: AsyncParsableCommand {
    /// The read-only commands that are the same at the top level and under
    /// `ro`. The type makes the compiler reject a command that does not
    /// conform to `ReadOnlyCommand`.
    static let sharedCommands: [any ReadOnlyCommand.Type] = [
        Accounts.self, Check.self, Mailboxes.self, List.self, Show.self, ThreadCommand.self,
    ]

    /// Everything under `ro`: the shared commands, then the read-only form of
    /// each group with both kinds (`auth` with only `status`), and of each
    /// write command whose options that write can be dropped (`download`
    /// without `-o`).
    static let commands: [any ReadOnlyCommand.Type] = sharedCommands + [ReadOnlyAuth.self, ReadOnlyDownload.self]

    static let configuration = CommandConfiguration(
        commandName: "ro",
        abstract: "Run a read-only command. Commands that change mail are not available here.",
        subcommands: commands.map { $0 as any ParsableCommand.Type }
    )
}
