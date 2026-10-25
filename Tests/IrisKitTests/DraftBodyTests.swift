import Foundation
import XCTest
@testable import IrisKit

/// The reply's source choice, with stubs for stdin and files: no test reads real stdin.
final class DraftBodyTests: XCTestCase {
    private struct NoSuchFile: Error, LocalizedError {
        var errorDescription: String? { "No such file." }
    }

    /// The reply from `argument` and `file`, with stdin holding `stdin` and the files in `files`.
    /// Fails the test when it reads a source that it should not.
    private func read(
        argument: String? = nil,
        file: String? = nil,
        attaching: Bool = false,
        stdinIsTerminal: Bool = false,
        stdin: Data? = nil,
        files: [String: Data] = [:]
    ) throws -> String {
        try DraftBody.read(
            argument: argument,
            file: file,
            attaching: attaching,
            stdinIsTerminal: stdinIsTerminal,
            readStdin: {
                guard let stdin else {
                    XCTFail("read stdin")
                    return Data()
                }
                return stdin
            },
            readFile: { path in
                guard let data = files[path] else {
                    throw NoSuchFile()
                }
                return data
            },
            fileExists: { files[$0] != nil }
        )
    }

    private func assertThrows(
        _ expected: IrisError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> String
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? IrisError, expected, file: file, line: line)
        }
    }

    // MARK: - Sources

    func testTheArgumentIsTheReply() throws {
        XCTAssertEqual(try read(argument: "Thanks!\n\n- one\n- two"), "Thanks!\n\n- one\n- two")
    }

    func testTheArgumentWinsOverStdinThatIsNotATerminal() throws {
        // A pipe that the user did not mean for iris, such as in a script, is not read.
        XCTAssertEqual(try read(argument: "Thanks!", stdinIsTerminal: false), "Thanks!")
    }

    func testFileIsReadByPath() throws {
        let reply = try read(file: "notes/reply.md", files: ["notes/reply.md": Data("From a *file*.\n".utf8)])
        XCTAssertEqual(reply, "From a *file*.\n")
    }

    func testDashFileReadsStdin() throws {
        XCTAssertEqual(try read(file: "-", stdin: Data("From stdin.".utf8)), "From stdin.")
    }

    func testDashFileReadsATerminalAfterSayingHowToEndIt() throws {
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }

        XCTAssertEqual(try read(file: "-", stdinIsTerminal: true, stdin: Data("Typed.".utf8)), "Typed.")
        XCTAssertEqual(recorder.lines, ["Reading the reply from stdin; end it with Ctrl-D."])
    }

    func testDashFileFromAPipeLogsNothing() throws {
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }

        _ = try read(file: "-", stdin: Data("Piped.".utf8))
        XCTAssertEqual(recorder.lines, [])
    }

    func testStdinIsReadWhenThereIsNoArgumentOrFileAndItIsNotATerminal() throws {
        XCTAssertEqual(try read(stdin: Data("Piped in.\n".utf8)), "Piped in.\n")
    }

    // MARK: - Errors

    func testAnArgumentAndAFileTogetherAreRejected() {
        assertThrows(.draftBodyGivenTwice) {
            try read(argument: "Thanks!", file: "reply.md", files: ["reply.md": Data("x".utf8)])
        }
        assertThrows(.draftBodyGivenTwice) { try read(argument: "Thanks!", file: "-", stdin: Data("x".utf8)) }
    }

    func testNoSourceWhileStdinIsATerminalIsRejectedWithoutWaiting() {
        assertThrows(.draftBodyMissing) { try read(stdinIsTerminal: true) }
    }

    func testAnEmptyOrWhitespaceReplyIsRejectedFromEverySource() {
        assertThrows(.draftBodyEmpty(source: "the argument")) { try read(argument: "") }
        assertThrows(.draftBodyEmpty(source: "the argument")) { try read(argument: " \n\t ") }
        assertThrows(.draftBodyEmpty(source: "the file \"empty.md\"")) {
            try read(file: "empty.md", files: ["empty.md": Data("\n\n".utf8)])
        }
        assertThrows(.draftBodyEmpty(source: "stdin")) { try read(stdin: Data()) }
        assertThrows(.draftBodyEmpty(source: "stdin")) { try read(file: "-", stdin: Data("  \r\n".utf8)) }
    }

    func testAFileThatCannotBeReadIsRejectedWithTheReason() {
        assertThrows(.draftBodyNotRead(source: "the file \"missing.md\"", reason: "No such file.")) {
            try read(file: "missing.md")
        }
    }

    /// `--attach a.pdf b.pdf`, or `--attach *.pdf` that matched two files, makes
    /// `b.pdf` the argument. The reply would be "b.pdf", and a reply piped on stdin would be lost.
    func testWithAttachmentsAnArgumentThatNamesAFileIsRejected() {
        assertThrows(.draftBodyNamesAFile(path: "b.pdf")) {
            try read(argument: "b.pdf", attaching: true, files: ["b.pdf": Data("%PDF".utf8)])
        }
        assertThrows(.draftBodyNamesAFile(path: "docs/b.pdf")) {
            try read(argument: "docs/b.pdf", attaching: true, files: ["docs/b.pdf": Data()])
        }
    }

    /// `-F reply.md --attach a.pdf b.pdf` makes `b.pdf` the argument next to -F:
    /// draftBodyNamesAFile says why, where draftBodyGivenTwice would not.
    func testWithAttachmentsAnArgumentThatNamesAFileWinsOverGivenTwice() {
        let files = ["reply.md": Data("From a file.".utf8), "b.pdf": Data("%PDF".utf8)]
        assertThrows(.draftBodyNamesAFile(path: "b.pdf")) {
            try read(argument: "b.pdf", file: "reply.md", attaching: true, files: files)
        }
        // stdin is nil, so the test fails if it is read.
        assertThrows(.draftBodyNamesAFile(path: "b.pdf")) {
            try read(argument: "b.pdf", file: "-", attaching: true, files: files)
        }
    }

    func testWithAttachmentsAnArgumentThatNamesNoFileAndAFileAreStillGivenTwice() {
        let files = ["reply.md": Data("From a file.".utf8)]
        assertThrows(.draftBodyGivenTwice) { try read(argument: "Thanks!", file: "reply.md", attaching: true, files: files) }
        assertThrows(.draftBodyGivenTwice) { try read(argument: "Thanks!", file: "-", attaching: true, stdin: Data("x".utf8)) }
    }

    func testWithAttachmentsAnArgumentThatNamesNoFileIsTheReply() throws {
        XCTAssertEqual(try read(argument: "Thanks!", attaching: true, files: ["a.pdf": Data()]), "Thanks!")
    }

    func testWithAttachmentsAReplyFromAFileOrStdinIsRead() throws {
        let files = ["reply.md": Data("From a file.".utf8)]
        XCTAssertEqual(try read(file: "reply.md", attaching: true, files: files), "From a file.")
        XCTAssertEqual(try read(attaching: true, stdin: Data("Piped.".utf8)), "Piped.")
    }

    /// Without --attach the check is off. (`-F a.md b.md` already fails as draftBodyGivenTwice.)
    func testWithoutAttachmentsAnArgumentThatNamesAFileIsTheReply() throws {
        XCTAssertEqual(try read(argument: "b.pdf", files: ["b.pdf": Data()]), "b.pdf")
    }

    func testAReplyThatIsNotUTF8IsRejected() {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9])  // "café" in ISO 8859-1
        assertThrows(.draftBodyNotUTF8(source: "the file \"latin1.md\"")) {
            try read(file: "latin1.md", files: ["latin1.md": latin1])
        }
        assertThrows(.draftBodyNotUTF8(source: "stdin")) { try read(stdin: latin1) }
    }
}
