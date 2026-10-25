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
                try await CLI.run(command, arguments: ["probe"], logDirectory: directory, settings: [:])
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
                XCTAssertTrue(text.contains("probe: No email account is configured."), text)
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
        let settings = ["IRIS_WORK_IMAP_PASSWORD": "private-password"]
        let log = try XCTUnwrap(IrisFileLog.openIfPossible(
            command: try Iris.parseAsRoot(["accounts"]), arguments: ["accounts"],
            directory: directory, settings: settings
        ))
        log.notice("first private-password")
        log.failure(IrisError.noAccountsConfigured, command: "accounts")
        var protocolLog = Logger(label: "SwiftMail")
        protocolLog.logLevel = .debug
        protocolLog.debug("protocol-payload-must-stay-out")
        await log.drain()

        let next = try IrisFileLog(directory: directory, settings: settings)
        next.notice("last line before exit")
        await next.drain()
        let text = try String(contentsOf: directory.appendingPathComponent("iris.log"), encoding: .utf8)
        XCTAssertTrue(text.contains("first <redacted>"), text)
        XCTAssertTrue(text.contains("accounts:"), text)
        XCTAssertTrue(text.contains("last line before exit"), text)
        XCTAssertFalse(text.contains("private-password"), text)
        XCTAssertFalse(text.contains("protocol-payload-must-stay-out"), text)
    }

    func testReadOnlyDoesNotCreateDirectoryOrPruneLogs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let arguments = ["ro", "accounts"]
        let command = try Iris.parseAsRoot(arguments)
        XCTAssertNil(IrisFileLog.openIfPossible(command: command, arguments: arguments, directory: directory, settings: [:]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldLog = directory.appendingPathComponent("iris-1.log")
        try Data("keep".utf8).write(to: oldLog)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: oldLog.path)
        XCTAssertNil(IrisFileLog.openIfPossible(command: command, arguments: arguments, directory: directory, settings: [:]))
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
        try await CLI.run(Probe(), arguments: ["probe"], logDirectory: file, settings: [:])
    }

    func testHelpAndGroupsDoNotOpenLogs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for arguments in [[], ["--help"], ["help", "accounts"], ["draft"], ["auth"]] {
            // Some help requests exit during parsing; others return the
            // parser's help command, which must not open a file either.
            if let command = try? Iris.parseAsRoot(arguments) {
                XCTAssertNil(IrisFileLog.openIfPossible(
                    command: command, arguments: arguments, directory: directory, settings: [:]
                ))
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
