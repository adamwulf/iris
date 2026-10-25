import ArgumentParser
import IrisKit
import XCTest
@testable import iris

final class ReadOnlyCommandTests: XCTestCase {
    private func names(_ commands: [any ParsableCommand.Type]) -> [String] {
        commands.map { $0._commandName }
    }

    func testRoHasOnlyTheReadOnlyCommands() {
        let roCommands = ReadOnly.configuration.subcommands
        XCTAssertEqual(names(roCommands), ["accounts", "check", "mailboxes", "list", "show", "thread", "auth", "download"])
        for command in roCommands + ReadOnlyAuth.configuration.subcommands {
            XCTAssertTrue(command is any ReadOnlyCommand.Type, "\(command) is under `iris ro` but is not a ReadOnlyCommand")
        }
    }

    func testEveryReadOnlyCommandIsAlsoUnderRo() {
        // `iris X` and `iris ro X` must offer the same read-only commands.
        let topLevelReadOnly = Iris.configuration.subcommands.filter { $0 is any ReadOnlyCommand.Type }
        XCTAssertEqual(names(topLevelReadOnly), names(ReadOnly.sharedCommands.map { $0 as any ParsableCommand.Type }))
        XCTAssertTrue(names(Iris.configuration.subcommands).contains("ro"))
        // `auth` has both kinds: its read-only children are under `iris ro auth` too.
        let readOnlyAuthChildren = Auth.configuration.subcommands.filter { $0 is any ReadOnlyCommand.Type }
        XCTAssertEqual(names(readOnlyAuthChildren), names(ReadOnlyAuth.configuration.subcommands))
        // The rest of `ro` is the read-only form of a top-level command that is not
        // read-only itself: `auth` (a group with both kinds) and `download` (without -o).
        let readOnlyForms: [any ParsableCommand.Type] = [ReadOnlyAuth.self, ReadOnlyDownload.self]
        let shared = names(ReadOnly.sharedCommands.map { $0 as any ParsableCommand.Type })
        XCTAssertEqual(names(ReadOnly.configuration.subcommands), shared + names(readOnlyForms))
        for form in readOnlyForms {
            let full = Iris.configuration.subcommands.first { $0._commandName == form._commandName }
            XCTAssertNotNil(full, "\(form) has no full form under `iris`")
            XCTAssertFalse(full is any ReadOnlyCommand.Type, "the full form of \(form) is a write command")
        }
    }

    func testRoDownloadParsesTheSameAsDownloadWithoutTheOutputPath() throws {
        let arguments = ["download", "work/Sent Items/42", "1.2"]
        let plain = try XCTUnwrap(try Iris.parseAsRoot(arguments) as? Download)
        let readOnly = try XCTUnwrap(try Iris.parseAsRoot(["ro"] + arguments) as? ReadOnlyDownload)

        for command in [plain.arguments, readOnly.arguments] {
            XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "Sent Items", uid: 42))
            XCTAssertEqual(command.attachmentID, try AttachmentID(parsing: "1.2"))
        }
        XCTAssertNil(plain.output)
    }

    func testDownloadWithAnOutputPathIsOnlyAtTheTop() throws {
        // -o writes a file whose content and name come from the sender.
        XCTAssertFalse(Download.self is any ReadOnlyCommand.Type)
        let download = try XCTUnwrap(try Iris.parseAsRoot(["download", "work/INBOX/42", "2", "-o", "x"]) as? Download)
        XCTAssertEqual(download.output, "x")
        XCTAssertTrue(try Iris.parseAsRoot(["ro", "download", "work/INBOX/42", "2"]) is ReadOnlyDownload)
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "download", "work/INBOX/42", "2", "-o", "x"]))
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "download", "work/INBOX/42", "2", "--output", "x"]))
    }

    func testRoListParsesTheSameAsList() throws {
        let arguments = ["list", "--mailbox", "Sent", "--page", "2", "--limit", "10", "--format", "json", "-a", "work"]
        let plain = try XCTUnwrap(try Iris.parseAsRoot(arguments) as? List)
        let readOnly = try XCTUnwrap(try Iris.parseAsRoot(["ro"] + arguments) as? List)

        for command in [plain, readOnly] {
            XCTAssertEqual(command.mailbox, "Sent")
            XCTAssertEqual(command.page, 2)
            XCTAssertEqual(command.limit, 10)
            XCTAssertEqual(command.format, .json)
            XCTAssertEqual(command.accountOptions.account, "work")
        }
    }

    func testRoShowParsesTheSameAsShow() throws {
        let arguments = ["show", "work/INBOX/42", "--format", "raw"]
        let plain = try XCTUnwrap(try Iris.parseAsRoot(arguments) as? Show)
        let readOnly = try XCTUnwrap(try Iris.parseAsRoot(["ro"] + arguments) as? Show)

        for command in [plain, readOnly] {
            XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
            XCTAssertEqual(command.format, .raw)
        }
    }

    func testRoThreadParsesTheSameAsThread() throws {
        let arguments = ["thread", "work/Sent/42", "--format", "json", "--body", "text"]
        let plain = try XCTUnwrap(try Iris.parseAsRoot(arguments) as? ThreadCommand)
        let readOnly = try XCTUnwrap(try Iris.parseAsRoot(["ro"] + arguments) as? ThreadCommand)

        for command in [plain, readOnly] {
            XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "Sent", uid: 42))
            XCTAssertEqual(command.format, .json)
            XCTAssertEqual(command.body, .text)
        }
    }

    func testWriteCommandsAreOnlyAtTheTop() {
        let topLevel = Iris.configuration.subcommands
        for command in [Read.self, Unread.self, Draft.self] as [any ParsableCommand.Type] {
            XCTAssertTrue(names(topLevel).contains(command._commandName), "\(command) is not under `iris`")
            XCTAssertFalse(names(ReadOnly.configuration.subcommands).contains(command._commandName), "\(command) is under `iris ro`")
            XCTAssertFalse(command is any ReadOnlyCommand.Type, "\(command) changes mail but is a ReadOnlyCommand")
        }
    }

    func testRoRejectsACommandThatIsNotReadOnly() throws {
        // The write commands parse at the top, but not under `ro`.
        XCTAssertTrue(try Iris.parseAsRoot(["read", "work/INBOX/42"]) is Read)
        XCTAssertTrue(try Iris.parseAsRoot(["unread", "work/INBOX/42"]) is Unread)
        let draft = try XCTUnwrap(try Iris.parseAsRoot(["draft", "work/INBOX/42", "Thanks!"]) as? Draft)
        XCTAssertEqual(draft.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "read", "work/INBOX/42"]))
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "unread", "work/INBOX/42"]))
        for arguments in [["ro", "draft"], ["ro", "draft", "work/INBOX/42", "Thanks!"], ["ro", "draft", "work/INBOX/42", "-F", "-"]] {
            XCTAssertThrowsError(try Iris.parseAsRoot(arguments), "\(arguments)")
        }
    }

    func testAuthLoginIsOnlyAtTheTopLevelAndAuthStatusIsInBoth() throws {
        // `auth login` opens a browser and writes .env; `auth status` only reads.
        XCTAssertFalse(Auth.self is any ReadOnlyCommand.Type)
        XCTAssertFalse(Auth.Login.self is any ReadOnlyCommand.Type)
        XCTAssertEqual(names(Auth.configuration.subcommands), ["login", "status"])
        XCTAssertEqual(names(ReadOnlyAuth.configuration.subcommands), ["status"])
        XCTAssertTrue(try Iris.parseAsRoot(["auth", "login"]) is Auth.Login)
        XCTAssertTrue(try Iris.parseAsRoot(["auth", "status"]) is Auth.Status)
        XCTAssertTrue(try Iris.parseAsRoot(["ro", "auth", "status"]) is Auth.Status, "the same leaf type")
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "auth", "login"]))
    }

    func testRoAuthStatusParsesTheSameAsAuthStatus() throws {
        let arguments = ["auth", "status", "--account", "personal", "--format", "json"]
        let plain = try XCTUnwrap(try Iris.parseAsRoot(arguments) as? Auth.Status)
        let readOnly = try XCTUnwrap(try Iris.parseAsRoot(["ro"] + arguments) as? Auth.Status)
        for command in [plain, readOnly] {
            XCTAssertEqual(command.account, "personal")
            XCTAssertEqual(command.format, .json)
        }
    }
}
