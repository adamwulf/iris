import ArgumentParser
import Foundation
import IrisKit
import Logging
import XCTest
@testable import iris

/// Exercise the executable's real backend wiring in temporary directories.
/// Only synthetic commands run: no network connection or global bootstrap.
final class FileLoggingTests: XCTestCase {
    private struct Probe: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "probe")
        enum Outcome: String, Decodable, CaseIterable {
            case success, irisError, exitStatus
        }
        var outcome: Outcome = .success

        func run() async throws {
            switch outcome {
            case .success: break
            case .irisError: throw IrisError.noAccountsConfigured
            case .exitStatus: throw ExitCode.failure
            }
        }
    }

    func testCommandPathsMatchCLIIncludingNestedCommands() {
        XCTAssertEqual(CLI.commandPath(for: Accounts.self), "accounts")
        XCTAssertEqual(CLI.commandPath(for: Auth.Status.self), "auth status")
        XCTAssertEqual(CLI.commandPath(for: Auth.Login.self), "auth login")
        XCTAssertEqual(CLI.commandPath(for: Draft.Reply.self), "draft reply")
        XCTAssertEqual(CLI.commandPath(for: Draft.Update.self), "draft update")
        XCTAssertEqual(CLI.commandPath(for: ThreadCommand.self), "thread")
    }

    func testLifecycleDrainsSuccessErrorsAndExitStatusesBeforeReturning() async throws {
        let previousHandler = IrisLog.handler
        let previousFileHandler = IrisLog.fileHandler
        defer {
            IrisLog.handler = previousHandler
            IrisLog.fileHandler = previousFileHandler
        }
        for outcome in Probe.Outcome.allCases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            var command = Probe()
            command.outcome = outcome
            var caught: Error?
            do {
                try await CLI.run(command, arguments: ["probe"], logDirectory: directory)
            } catch {
                caught = error
            }

            // No test-side drain: run must finish the pending writes itself.
            let text = try String(contentsOf: directory.appendingPathComponent("iris.log"), encoding: .utf8)
            XCTAssertTrue(text.contains("Starting probe."), text)
            switch outcome {
            case .success:
                XCTAssertNil(caught)
                XCTAssertTrue(text.contains("Completed probe."), text)
            case .irisError:
                XCTAssertEqual(caught as? IrisError, .noAccountsConfigured)
                XCTAssertTrue(text.contains("probe: no_accounts_configured."), text)
                XCTAssertTrue(text.contains("ERROR"), text)
                XCTAssertFalse(text.contains("Completed probe."), text)
            case .exitStatus:
                XCTAssertEqual(caught as? ExitCode, .failure)
                XCTAssertTrue(text.contains("probe: exited with status 1."), text)
                XCTAssertFalse(text.contains("ERROR"), text)
                XCTAssertFalse(text.contains("did not complete"), text)
            }
        }
    }

    func testFileDestinationAppendsAndDrainsWithoutCapturingOtherLoggers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = try XCTUnwrap(IrisFileLog.openIfPossible(
            command: try Iris.parseAsRoot(["accounts"]), arguments: ["accounts"],
            directory: directory
        ))
        // Open both handles before writing: without O_APPEND the second
        // writer would overwrite the first writer's records at its old offset.
        let next = try IrisFileLog(directory: directory)
        log.record(.started, command: Accounts.self)
        log.record(.googleSignInStarted)
        let sensitive = "private-password private-account https://private.example key token mail-subject mail-body"
        log.record(.failed(IrisError.serverError(account: sensitive, command: sensitive, reason: sensitive)), command: Accounts.self)
        var protocolLog = Logger(label: "SwiftMail")
        protocolLog.logLevel = .debug
        protocolLog.debug("protocol-payload-must-stay-out")
        await log.drain()

        next.record(.completed, command: Accounts.self)
        await next.drain()
        log.record(.logoutFailed)
        await log.drain()
        let text = try String(contentsOf: directory.appendingPathComponent("iris.log"), encoding: .utf8)
        XCTAssertTrue(text.contains("Starting accounts."), text)
        XCTAssertTrue(text.contains("accounts: server_error."), text)
        XCTAssertTrue(text.contains("Completed accounts."), text)
        XCTAssertTrue(text.contains("google_sign_in_started"), text)
        XCTAssertTrue(text.contains("logout_failed"), text)
        XCTAssertTrue(text.contains("FileLoggingTests"), text)
        XCTAssertFalse(text.contains("IrisFileLog.swift"), text)
        for value in sensitive.split(separator: " ") {
            XCTAssertFalse(text.contains(value), text)
        }
        XCTAssertFalse(text.contains("protocol-payload-must-stay-out"), text)
    }

    func testReadOnlyDoesNotCreateDirectoryOrPruneLogs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let arguments = ["ro", "accounts"]
        let command = try Iris.parseAsRoot(arguments)
        XCTAssertNil(IrisFileLog.openIfPossible(command: command, arguments: arguments, directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldLog = directory.appendingPathComponent("iris-1.log")
        try Data("keep".utf8).write(to: oldLog)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: oldLog.path)
        XCTAssertNil(IrisFileLog.openIfPossible(command: command, arguments: arguments, directory: directory))
        XCTAssertEqual(try Data(contentsOf: oldLog), Data("keep".utf8))
    }

    func testUnavailableDirectoryDoesNotPreventCommandStartup() async throws {
        let previousHandler = IrisLog.handler
        let previousFileHandler = IrisLog.fileHandler
        defer {
            IrisLog.handler = previousHandler
            IrisLog.fileHandler = previousFileHandler
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        try await CLI.run(Probe(), arguments: ["probe"], logDirectory: file)
    }

    func testHelpAndGroupsDoNotOpenLogs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for arguments in [[], ["--help"], ["help", "accounts"], ["draft"], ["auth"]] {
            // Some help requests exit during parsing; others return the
            // parser's help command, which must not open a file either.
            if let command = try? Iris.parseAsRoot(arguments) {
                XCTAssertNil(IrisFileLog.openIfPossible(
                    command: command, arguments: arguments, directory: directory
                ))
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
