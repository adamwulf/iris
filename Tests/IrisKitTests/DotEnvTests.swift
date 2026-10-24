import Foundation
import XCTest
@testable import IrisKit

final class DotEnvTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotEnvTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testParseSkipsCommentsBlankLinesAndMalformedLines() {
        let values = DotEnv.parse("""
        # a comment

        PLAIN=value
        export EXPORTED=skipped
        SPACED = skipped
        NO_EQUALS
        """)
        XCTAssertEqual(values, ["PLAIN": "value"])
    }

    func testParseRemovesOnePairOfMatchingQuotes() {
        let values = DotEnv.parse("""
        DOUBLE="a b"
        SINGLE='c d'
        MISMATCHED="e'
        NESTED=""f""
        """)
        XCTAssertEqual(values["DOUBLE"], "a b")
        XCTAssertEqual(values["SINGLE"], "c d")
        XCTAssertEqual(values["MISMATCHED"], "\"e'")
        XCTAssertEqual(values["NESTED"], "\"f\"")
    }

    func testParseKeepsEqualsSignsInTheValue() {
        XCTAssertEqual(DotEnv.parse("PASSWORD=a=b=c")["PASSWORD"], "a=b=c")
    }

    func testParseTreatsEmptyValuesAsNotSetAndFirstValueWins() {
        let values = DotEnv.parse("""
        EMPTY=
        QUOTED_EMPTY=""
        TWICE=first
        TWICE=second
        """)
        XCTAssertNil(values["EMPTY"])
        XCTAssertNil(values["QUOTED_EMPTY"])
        XCTAssertEqual(values["TWICE"], "first")
    }

    func testParseHandlesWindowsLineEndings() {
        XCTAssertEqual(DotEnv.parse("A=1\r\nB=2\r\n"), ["A": "1", "B": "2"])
    }

    func testLoadAllMergesParentFilesAndTheNearerFileWins() throws {
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "SHARED=parent\nPARENT_ONLY=p\nEMPTY_IN_CHILD=parent".write(
            to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "SHARED=child\nCHILD_ONLY=c\nEMPTY_IN_CHILD=".write(
            to: child.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let values = DotEnv.loadAll(startingIn: child)

        XCTAssertEqual(values["SHARED"], "child")
        XCTAssertEqual(values["PARENT_ONLY"], "p")
        XCTAssertEqual(values["CHILD_ONLY"], "c")
        XCTAssertEqual(values["EMPTY_IN_CHILD"], "parent")
    }

    func testCandidateFileURLsGoFromTheDirectoryUpToTheRoot() {
        let urls = DotEnv.candidateFileURLs(startingIn: URL(fileURLWithPath: "/a/b"))
        XCTAssertEqual(urls.map(\.path), ["/a/b/.env", "/a/.env", "/.env"])
    }
}
