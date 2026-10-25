import Foundation
import XCTest
@testable import IrisKit

/// Where `iris download` puts the bytes: stdout, or a new file at exactly the
/// path given. Files go to a temporary directory of each test.
final class AttachmentOutputTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentOutputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// The bytes of an attachment, not UTF-8 text.
    private let pdf = Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])

    private func path(_ name: String) -> String {
        directory.appendingPathComponent(name).path
    }

    private func contents(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func assertThrows(
        _ expected: IrisError, _ body: () throws -> Any, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? IrisError, expected, file: file, line: line)
        }
    }

    // MARK: - Choosing the output

    func testWithoutAPathTheBytesGoToStdoutUnchanged() throws {
        let output = try AttachmentOutput(path: nil, stdoutIsTerminal: false)

        XCTAssertEqual(output, .stdout)
        XCTAssertEqual(try output.write(pdf), pdf, "the bytes and nothing else, as show --format raw")
    }

    func testWithoutAPathATerminalOnStdoutFails() {
        assertThrows(.attachmentStdoutIsTerminal) { try AttachmentOutput(path: nil, stdoutIsTerminal: true) }
    }

    func testWithAPathStdoutMayBeATerminal() throws {
        let target = path("Q4.pdf")
        XCTAssertEqual(try AttachmentOutput(path: target, stdoutIsTerminal: true), .file(path: target))
        XCTAssertEqual(try AttachmentOutput(path: target, stdoutIsTerminal: false), .file(path: target))
        XCTAssertEqual(try AttachmentOutput(path: "out.pdf", stdoutIsTerminal: true), .file(path: "out.pdf"))
    }

    func testAFolderIsNotAPathToWrite() throws {
        let link = path("link-to-folder")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory.path)

        for folder in [directory.path, directory.path + "/", link] {
            assertThrows(.attachmentOutputIsFolder(path: folder)) {
                try AttachmentOutput(path: folder, stdoutIsTerminal: false)
            }
        }
    }

    /// Before the download, so iris does not download for nothing.
    func testAnythingAtThePathIsFoundBeforeTheDownload() throws {
        let file = path("Q4.pdf")
        try Data("mine".utf8).write(to: URL(fileURLWithPath: file))
        let linkToFile = path("link.pdf")
        try FileManager.default.createSymbolicLink(atPath: linkToFile, withDestinationPath: file)
        let dangling = path("dangling.pdf")
        try FileManager.default.createSymbolicLink(atPath: dangling, withDestinationPath: path("nowhere.pdf"))

        for taken in [file, linkToFile, dangling] {
            assertThrows(.attachmentFileExists(path: taken)) {
                try AttachmentOutput(path: taken, stdoutIsTerminal: false)
            }
        }
    }

    /// A typo in the folder, or a folder not made yet, fails before the download.
    func testAPathWhoseFolderIsMissingIsFoundBeforeTheDownload() throws {
        let missing = path("Dowloads/report.pdf")
        assertThrows(.attachmentNotSaved(path: missing, reason: "the folder \"\(path("Dowloads"))\" does not exist")) {
            try AttachmentOutput(path: missing, stdoutIsTerminal: false)
        }

        let file = path("notes.txt")
        try Data("mine".utf8).write(to: URL(fileURLWithPath: file))
        let underAFile = path("notes.txt/report.pdf")
        assertThrows(.attachmentNotSaved(path: underAFile, reason: "\"\(file)\" is not a folder")) {
            try AttachmentOutput(path: underAFile, stdoutIsTerminal: false)
        }

        // Its own folder exists, but the write would make a file named new-folder.
        let newFolder = directory.path + "/new-folder/"
        assertThrows(.attachmentNotSaved(
            path: newFolder,
            reason: "the path ends in \"/\", so it names a folder, and -o takes the path of the file to write: add a file name"
        )) {
            try AttachmentOutput(path: newFolder, stdoutIsTerminal: false)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("new-folder")))
    }

    func testAPathInALinkToAFolderOrInTheCurrentFolderIsFine() throws {
        let link = path("link-to-folder")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory.path)
        let inLink = link + "/report.pdf"
        XCTAssertEqual(try AttachmentOutput(path: inLink, stdoutIsTerminal: false), .file(path: inLink))
        let bareName = "iris-test-\(UUID().uuidString).pdf"
        XCTAssertEqual(
            try AttachmentOutput(path: bareName, stdoutIsTerminal: false), .file(path: bareName),
            "a bare file name is in the current folder"
        )
    }

    // MARK: - Saving

    func testAPathIsTheFileToWriteAndNothingIsPrinted() throws {
        let target = path("Q4.pdf")

        let stdout = try AttachmentOutput.file(path: target).write(pdf)

        XCTAssertEqual(stdout, Data(), "as read and unread, nothing on success")
        XCTAssertEqual(try contents(target), pdf)
    }

    func testAnExistingFileIsNeverOverwritten() throws {
        let target = path("Q4.pdf")
        try Data("mine".utf8).write(to: URL(fileURLWithPath: target))

        assertThrows(.attachmentFileExists(path: target)) { try AttachmentOutput.file(path: target).write(self.pdf) }

        XCTAssertEqual(try contents(target), Data("mine".utf8))
    }

    func testASymbolicLinkInTheWayIsNotFollowed() throws {
        let elsewhere = path("elsewhere.txt")
        try Data("mine".utf8).write(to: URL(fileURLWithPath: elsewhere))
        let link = path("Q4.pdf")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: elsewhere)
        let dangling = path("dangling.pdf")
        try FileManager.default.createSymbolicLink(atPath: dangling, withDestinationPath: path("nowhere.pdf"))

        assertThrows(.attachmentFileExists(path: link)) { try AttachmentOutput.file(path: link).write(self.pdf) }
        assertThrows(.attachmentFileExists(path: dangling)) { try AttachmentOutput.file(path: dangling).write(self.pdf) }

        XCTAssertEqual(try contents(elsewhere), Data("mine".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("nowhere.pdf")))
    }

    /// A folder made after the output was chosen: the write fails, and nothing goes inside it.
    func testAFolderAtThePathWhenWritingIsNotWrittenInto() throws {
        XCTAssertThrowsError(try AttachmentOutput.file(path: directory.path).write(pdf))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testAFolderThatDoesNotExistIsNotSaved() throws {
        let target = path("missing/Q4.pdf")

        XCTAssertThrowsError(try AttachmentOutput.file(path: target).write(pdf)) { error in
            guard case .attachmentNotSaved(let failedPath, _) = error as? IrisError else {
                return XCTFail("expected attachmentNotSaved, got \(error)")
            }
            XCTAssertEqual(failedPath, target)
        }
    }
}
