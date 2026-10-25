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

    private let pdf = DownloadedAttachment(
        attachmentID: AttachmentID(components: [2]), data: Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])
    )

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
        XCTAssertEqual(try output.write(pdf), pdf.data, "the bytes and nothing else, as show --format raw")
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

    func testTheTerminalErrorSaysToRedirectOrPassAPath() throws {
        let message = try XCTUnwrap(IrisError.attachmentStdoutIsTerminal.errorDescription)
        XCTAssertTrue(message.contains("stdout is a terminal"), message)
        XCTAssertTrue(message.contains("`iris download '<iris-id>' <attachment-id> > <file>`"), message)
        XCTAssertTrue(message.contains("-o <path>"), message)
        XCTAssertTrue(message.contains("`iris ro download` has no -o"), message)
    }

    func testTheFolderErrorSaysToAddAFileName() {
        XCTAssertEqual(
            IrisError.attachmentOutputIsFolder(path: "Downloads").errorDescription,
            "\"Downloads\" is a folder, and -o takes the path of the file to write. Add a file name, "
                + "such as the filename that `iris show` lists for the attachment: -o 'Downloads/<file name>'."
        )
        XCTAssertEqual(
            IrisError.attachmentOutputIsFolder(path: "/Users/me/Bob's files/").errorDescription,
            "\"/Users/me/Bob's files/\" is a folder, and -o takes the path of the file to write. Add a file name, "
                + #"such as the filename that `iris show` lists for the attachment: -o '/Users/me/Bob'\''s files/<file name>'."#
        )
    }

    // MARK: - Saving

    func testAPathIsTheFileToWriteAndNothingIsPrinted() throws {
        let target = path("Q4.pdf")

        let stdout = try AttachmentOutput.file(path: target).write(pdf)

        XCTAssertEqual(stdout, Data(), "as read and unread, nothing on success")
        XCTAssertEqual(try contents(target), pdf.data)
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

    func testTheFileErrorsSayToPassAnotherPath() {
        XCTAssertEqual(
            IrisError.attachmentFileExists(path: "report.pdf").errorDescription,
            "The file \"report.pdf\" already exists, and iris never overwrites a file. Pass -o with another path."
        )
        XCTAssertEqual(
            IrisError.attachmentNotSaved(path: "x/report.pdf", reason: "No such file or directory.").errorDescription,
            "Could not save the attachment to \"x/report.pdf\" (No such file or directory.). "
                + "Check that the folder exists and that you can write to it, or pass -o with another path."
        )
    }
}
