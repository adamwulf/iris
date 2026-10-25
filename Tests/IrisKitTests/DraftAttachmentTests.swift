import Foundation
import XCTest
@testable import IrisKit

/// Reading the files of `iris draft --attach`, in a temporary directory.
final class DraftAttachmentTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `data` to `name` in the temporary directory and gives its path.
    private func file(_ name: String, _ data: Data) throws -> String {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url.path
    }

    func testAFileGivesItsNameItsTypeAndItsBytes() throws {
        let bytes = Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF, 0x0D, 0x0A])
        let path = try file("Q4 plan.pdf", bytes)

        XCTAssertEqual(
            try DraftAttachment.read(path: path),
            DraftAttachment(filename: "Q4 plan.pdf", mimeType: "application/pdf", data: bytes)
        )
    }

    /// The MIME type of a one-byte file named `name`.
    private func mimeType(of name: String) throws -> String {
        try DraftAttachment.read(path: try file(name, Data("x".utf8))).mimeType
    }

    func testTheTypeComesFromTheExtensionInAnyCase() throws {
        XCTAssertEqual(try mimeType(of: "NOTES.TXT"), "text/plain")
        XCTAssertEqual(try mimeType(of: "budget.xlsx"), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    }

    func testAFileWithoutAKnownExtensionIsOctetStream() throws {
        XCTAssertEqual(try mimeType(of: "Makefile"), "application/octet-stream")
        XCTAssertEqual(try mimeType(of: "data.irisunknown"), "application/octet-stream")
    }

    func testAnEmptyFileIsAttached() throws {
        let attachment = try DraftAttachment.read(path: try file("empty.txt", Data()))
        XCTAssertEqual(attachment, DraftAttachment(filename: "empty.txt", mimeType: "text/plain", data: Data()))
    }

    func testAMissingFileIsNotReadAndTheErrorNamesThePath() {
        let path = root.appendingPathComponent("missing.pdf").path

        XCTAssertThrowsError(try DraftAttachment.read(path: path)) { error in
            guard case .draftAttachmentNotRead(let errorPath, let reason)? = error as? IrisError else {
                return XCTFail("expected draftAttachmentNotRead, got \(error)")
            }
            XCTAssertEqual(errorPath, path)
            XCTAssertFalse(reason.isEmpty, "Foundation's reason, such as \"there is no such file\"")
        }
    }

    func testAFolderIsRejected() {
        XCTAssertThrowsError(try DraftAttachment.read(path: root.path)) { error in
            XCTAssertEqual(error as? IrisError, .draftAttachmentIsAFolder(path: root.path))
        }
    }

    func testAFileThatCannotBeReadIsNotRead() throws {
        // Root reads any file, so the test means nothing there.
        try XCTSkipIf(getuid() == 0, "root can read a file without permissions")
        let path = try file("locked.txt", Data("secret plan".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)

        XCTAssertThrowsError(try DraftAttachment.read(path: path)) { error in
            guard case .draftAttachmentNotRead(let errorPath, _)? = error as? IrisError else {
                return XCTFail("expected draftAttachmentNotRead, got \(error)")
            }
            XCTAssertEqual(errorPath, path)
        }
    }
}
