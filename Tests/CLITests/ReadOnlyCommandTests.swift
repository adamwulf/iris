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
        XCTAssertEqual(names(roCommands), ["accounts", "check", "mailboxes", "list", "show", "thread", "auth"])
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

    func testReadAndUnreadAreWriteCommandsOnlyAtTheTop() {
        let topLevel = Iris.configuration.subcommands
        for command in [Read.self, Unread.self] as [any ParsableCommand.Type] {
            XCTAssertTrue(names(topLevel).contains(command._commandName), "\(command) is not under `iris`")
            XCTAssertFalse(command is any ReadOnlyCommand.Type, "\(command) changes mail but is a ReadOnlyCommand")
        }
    }

    func testRoRejectsACommandThatIsNotReadOnly() throws {
        // The write commands parse at the top, but not under `ro`.
        XCTAssertTrue(try Iris.parseAsRoot(["read", "work/INBOX/42"]) is Read)
        XCTAssertTrue(try Iris.parseAsRoot(["unread", "work/INBOX/42"]) is Unread)
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "read", "work/INBOX/42"]))
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "unread", "work/INBOX/42"]))
        // There is no `draft` yet; when it exists, it must still fail here.
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "draft"]))
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
