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
        XCTAssertEqual(names(roCommands), ["accounts", "check", "mailboxes", "list", "show"])
        for command in roCommands {
            XCTAssertTrue(command is any ReadOnlyCommand.Type, "\(command) is under `iris ro` but is not a ReadOnlyCommand")
        }
    }

    func testEveryReadOnlyCommandIsAlsoUnderRo() {
        // `iris X` and `iris ro X` must offer the same read-only commands.
        let topLevelReadOnly = Iris.configuration.subcommands.filter { $0 is any ReadOnlyCommand.Type }
        XCTAssertEqual(names(topLevelReadOnly), names(ReadOnly.configuration.subcommands))
        XCTAssertTrue(names(Iris.configuration.subcommands).contains("ro"))
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

    func testAuthIsAWriteCommandOnlyAtTheTopLevel() throws {
        // `auth login` opens a browser and writes .env.
        XCTAssertFalse(Auth.self is any ReadOnlyCommand.Type)
        XCTAssertFalse(Auth.Login.self is any ReadOnlyCommand.Type)
        XCTAssertTrue(names(Iris.configuration.subcommands).contains("auth"))
        XCTAssertFalse(names(ReadOnly.configuration.subcommands).contains("auth"))
        XCTAssertTrue(try Iris.parseAsRoot(["auth", "login"]) is Auth.Login)
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "auth", "login"]))
        XCTAssertThrowsError(try Iris.parseAsRoot(["ro", "auth"]))
    }
}
