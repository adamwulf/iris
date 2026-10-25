import Foundation
import XCTest
@testable import IrisKit

/// Where `iris download` puts the bytes: stdout, or a new file. Files go to a
/// temporary directory of each test.
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
        attachmentID: AttachmentID(components: [2]), filename: "report.pdf", data: Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])
    )

    private func path(_ name: String) -> String {
        directory.appendingPathComponent(name).path
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
        XCTAssertEqual(try AttachmentOutput(path: "out.pdf", stdoutIsTerminal: true), .file(path: "out.pdf"))
        XCTAssertEqual(try AttachmentOutput(path: "out.pdf", stdoutIsTerminal: false), .file(path: "out.pdf"))
    }

    func testTheTerminalErrorSaysToRedirectOrPassAPath() throws {
        let message = try XCTUnwrap(IrisError.attachmentStdoutIsTerminal.errorDescription)
        XCTAssertTrue(message.contains("stdout is a terminal"), message)
        XCTAssertTrue(message.contains("`iris download '<iris-id>' <attachment-id> > <file>`"), message)
        XCTAssertTrue(message.contains("-o <path>"), message)
        XCTAssertTrue(message.contains("`iris ro download` has no -o"), message)
    }

    // MARK: - Saving

    func testAPathThatIsNotADirectoryNamesTheFile() throws {
        let target = path("Q4.pdf")

        let stdout = try AttachmentOutput.file(path: target).write(pdf)

        XCTAssertEqual(String(decoding: stdout, as: UTF8.self), target + "\n", "the saved path and a newline")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: target)), pdf.data)
    }

    func testADirectoryGetsTheFileUnderTheAttachmentsFilename() throws {
        for directoryPath in [directory.path, directory.path + "/"] {
            let saved = try AttachmentOutput.save(pdf, to: directoryPath)
            XCTAssertEqual(saved, path("report.pdf"))
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: saved)), pdf.data)
            try FileManager.default.removeItem(atPath: saved)
        }
    }

    func testAnExistingFileIsNeverOverwritten() throws {
        let target = path("Q4.pdf")
        try Data("mine".utf8).write(to: URL(fileURLWithPath: target))

        assertThrows(.attachmentFileExists(path: target)) { try AttachmentOutput.file(path: target).write(self.pdf) }
        assertThrows(.attachmentFileExists(path: path("report.pdf"))) {
            try Data("mine".utf8).write(to: URL(fileURLWithPath: self.path("report.pdf")))
            return try AttachmentOutput.file(path: self.directory.path).write(self.pdf)
        }

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: target)), Data("mine".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path("report.pdf"))), Data("mine".utf8))
    }

    func testASymbolicLinkInTheWayIsNotFollowed() throws {
        let elsewhere = path("elsewhere.txt")
        try Data("mine".utf8).write(to: URL(fileURLWithPath: elsewhere))
        try FileManager.default.createSymbolicLink(atPath: path("report.pdf"), withDestinationPath: elsewhere)
        let dangling = path("dangling.pdf")
        try FileManager.default.createSymbolicLink(atPath: dangling, withDestinationPath: path("nowhere.pdf"))

        assertThrows(.attachmentFileExists(path: path("report.pdf"))) { try AttachmentOutput.save(self.pdf, to: self.directory.path) }
        assertThrows(.attachmentFileExists(path: dangling)) { try AttachmentOutput.save(self.pdf, to: dangling) }

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: elsewhere)), Data("mine".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("nowhere.pdf")))
    }

    func testAFolderThatDoesNotExistIsNotSaved() throws {
        let target = path("missing/Q4.pdf")

        XCTAssertThrowsError(try AttachmentOutput.save(pdf, to: target)) { error in
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

    // MARK: - Safe filenames

    private func safe(_ filename: String?, _ id: [Int] = [2]) -> String {
        AttachmentOutput.safeFilename(filename, attachmentID: AttachmentID(components: id))
    }

    func testASafeFilenameIsKept() {
        XCTAssertEqual(safe("report.pdf"), "report.pdf")
        XCTAssertEqual(safe("Résumé 2026 (final).pdf"), "Résumé 2026 (final).pdf")
        XCTAssertEqual(safe("photo 📷.jpg"), "photo 📷.jpg")
        XCTAssertEqual(safe("archive.tar.gz"), "archive.tar.gz")
        XCTAssertEqual(safe("v1..2.txt"), "v1..2.txt", "dots inside the name are fine")
    }

    func testOnlyTheLastPathComponentIsUsed() {
        XCTAssertEqual(safe("../../.ssh/authorized_keys"), "authorized_keys")
        XCTAssertEqual(safe("/etc/passwd"), "passwd")
        XCTAssertEqual(safe(#"C:\Users\Jane\report.pdf"#), "report.pdf")
        XCTAssertEqual(safe(#"docs\..\report.pdf"#), "report.pdf")
        XCTAssertEqual(safe("docs/report.pdf/"), "report.pdf")
    }

    func testControlCharactersAreRemoved() {
        XCTAssertEqual(safe("report\u{0}.pdf"), "report.pdf")
        XCTAssertEqual(safe("re\nport\t.pdf"), "report.pdf")
        XCTAssertEqual(safe("\u{1B}[31mred.txt"), "[31mred.txt")
        XCTAssertEqual(safe("invoice\u{202E}fdp.exe"), "invoicefdp.exe", "no right-to-left override")
    }

    func testANameIsNeverDotDotDotOrHidden() {
        XCTAssertEqual(safe(".zshrc"), "zshrc")
        XCTAssertEqual(safe("...secret"), "secret")
        XCTAssertEqual(safe(" .zshrc"), "zshrc")
        XCTAssertEqual(safe(" report.pdf "), "report.pdf")
        XCTAssertEqual(safe("a/.."), "attachment-2")
        XCTAssertEqual(safe("."), "attachment-2")
        XCTAssertEqual(safe(".."), "attachment-2")
    }

    func testNoUsableNameGivesTheFallbackWithTheAttachmentID() {
        XCTAssertEqual(safe(nil), "attachment-2")
        XCTAssertEqual(safe(nil, [1, 2]), "attachment-1.2")
        for unusable in ["", "/", "\\", "///", " ", "\u{0}", "\u{7}\u{8}", ". ."] {
            XCTAssertEqual(safe(unusable), "attachment-2", "\(unusable.debugDescription)")
        }
    }

    func testADirectoryUsesTheFallbackWhenTheAttachmentHasNoFilename() throws {
        let unnamed = DownloadedAttachment(attachmentID: AttachmentID(components: [1, 2]), filename: nil, data: Data("x".utf8))

        XCTAssertEqual(try AttachmentOutput.save(unnamed, to: directory.path), path("attachment-1.2"))
    }
}
