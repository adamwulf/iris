import Foundation
import IrisKit
import Logging
import XCTest
@testable import iris

/// Exercise the executable's real backend wiring in temporary directories.
/// No command runs, network connection, or global logging bootstrap.
final class FileLoggingTests: XCTestCase {
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

    func testUnavailableDirectoryDoesNotPreventCommandStartup() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        XCTAssertNil(IrisFileLog.openIfPossible(
            command: try Iris.parseAsRoot(["accounts"]), arguments: ["accounts"], directory: file, settings: [:]
        ))
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
