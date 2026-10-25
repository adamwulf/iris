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
          # an indented comment

        PLAIN=value
        SPACED = skipped
        export SPACED_TOO = skipped
        NO_EQUALS
        export
        """)
        XCTAssertEqual(values, ["PLAIN": "value"])
    }

    func testParseAcceptsAnExportPrefix() {
        let values = DotEnv.parse("""
        export A=1
        export   B="2"
        export\tC=3
        exportD=4
        """)
        XCTAssertEqual(values, ["A": "1", "B": "2", "C": "3", "exportD": "4"])
    }

    func testParseRemovesAnInlineCommentFromAnUnquotedValue() {
        let values = DotEnv.parse("""
        HOST=imap.gmail.com  # Gmail
        PORT=993\t# TLS
        PASSWORD=p#ss
        TWO=a # b # c
        ONLY_A_COMMENT= # nothing here
        """)
        XCTAssertEqual(values["HOST"], "imap.gmail.com")
        XCTAssertEqual(values["PORT"], "993")
        XCTAssertEqual(values["PASSWORD"], "p#ss", "a # with no whitespace before it is part of the value")
        XCTAssertEqual(values["TWO"], "a")
        XCTAssertNil(values["ONLY_A_COMMENT"])
    }

    func testParseKeepsAHashInAQuotedValueAndAllowsACommentAfterIt() {
        let values = DotEnv.parse("""
        DOUBLE="p # ss"
        SINGLE='a # b'
        COMMENTED="secret" # personal
        QUOTES_IN_COMMENT="abc" # say "hi"
        GLUED="abc"#not a comment
        """)
        XCTAssertEqual(values["DOUBLE"], "p # ss")
        XCTAssertEqual(values["SINGLE"], "a # b")
        XCTAssertEqual(values["COMMENTED"], "secret")
        XCTAssertEqual(values["QUOTES_IN_COMMENT"], "abc")
        XCTAssertEqual(values["GLUED"], "\"abc\"#not a comment")
    }

    func testParseRemovesOnePairOfMatchingQuotes() {
        let values = DotEnv.parse("""
        DOUBLE="a b"
        SINGLE='c d'
        MISMATCHED="e'
        NESTED=""f""
        INNER="ab"cd"
        """)
        XCTAssertEqual(values["DOUBLE"], "a b")
        XCTAssertEqual(values["SINGLE"], "c d")
        XCTAssertEqual(values["MISMATCHED"], "\"e'")
        XCTAssertEqual(values["NESTED"], "\"f\"")
        XCTAssertEqual(values["INNER"], "ab\"cd")
    }

    func testParseKeepsEqualsSignsInTheValue() {
        XCTAssertEqual(DotEnv.parse("PASSWORD=a=b=c")["PASSWORD"], "a=b=c")
    }

    func testParseTreatsEmptyValuesAsNotSetAndTheLastLineWins() {
        let values = DotEnv.parse("""
        EMPTY=
        QUOTED_EMPTY=""
        TWICE=first
        TWICE=second
        CLEARED=value
        CLEARED=
        """)
        XCTAssertNil(values["EMPTY"])
        XCTAssertNil(values["QUOTED_EMPTY"])
        XCTAssertEqual(values["TWICE"], "second")
        XCTAssertNil(values["CLEARED"], "an empty last line unsets the key, as `source` does")
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

    // MARK: - Writing

    private func writeEnv(_ text: String, in directory: URL? = nil) throws -> URL {
        let directory = directory ?? root!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(".env")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func setValue(_ value: String, forKey key: String, in text: String) throws -> String {
        let fileURL = try writeEnv(text)
        try DotEnv.setValue(value, forKey: key, in: fileURL)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func testFileURLSettingKeyFindsTheNearestFileThatSetsTheKey() throws {
        let child = root.appendingPathComponent("child", isDirectory: true)
        let parentFile = try writeEnv("K=parent\n")
        let childFile = try writeEnv("OTHER=x\n", in: child)
        XCTAssertEqual(DotEnv.fileURL(settingKey: "K", startingIn: child), parentFile, "the child does not set K")

        try "K=\n".write(to: childFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(DotEnv.fileURL(settingKey: "K", startingIn: child), parentFile, "an empty value does not count")

        try "export K=child\n".write(to: childFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(DotEnv.fileURL(settingKey: "K", startingIn: child), childFile)

        XCTAssertNil(DotEnv.fileURL(settingKey: "IRIS_TEST_KEY_THAT_NO_FILE_SETS", startingIn: child))
    }

    func testSetValueReplacesTheFirstLineAndDropsLaterLinesOfTheKey() throws {
        let text = try setValue("new", forKey: "K", in: """
        A=1
        K=old
        # K=a comment stays
        B=2
        export K=older
        K_EXTRA=other key
        """)
        XCTAssertEqual(text, "A=1\nK=new\n# K=a comment stays\nB=2\nK_EXTRA=other key\n")
        XCTAssertEqual(DotEnv.parse(text)["K"], "new")
    }

    func testSetValueReplacesALineWithAnEmptyValue() throws {
        XCTAssertEqual(try setValue("new", forKey: "K", in: "K=\nA=1\n"), "K=new\nA=1\n")
    }

    func testSetValueAppendsALineAfterAFinalNewline() throws {
        XCTAssertEqual(try setValue("new", forKey: "K", in: "A=1\n\n# end\n"), "A=1\n\n# end\nK=new\n")
    }

    func testSetValueAppendsALineWithoutAFinalNewline() throws {
        XCTAssertEqual(try setValue("new", forKey: "K", in: "A=1"), "A=1\nK=new\n")
        XCTAssertEqual(try setValue("new", forKey: "K", in: ""), "K=new\n")
    }

    func testSetValueKeepsThePermissions() throws {
        let fileURL = try writeEnv("A=1\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        try DotEnv.setValue("new", forKey: "K", in: fileURL)

        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testSetValueWritesTheFileThatALinkPointsTo() throws {
        let real = root.appendingPathComponent("dotfiles", isDirectory: true)
        let realFile = try writeEnv("A=1\n", in: real)
        let link = root.appendingPathComponent(".env")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realFile)

        try DotEnv.setValue("new", forKey: "K", in: link)

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), realFile.path)
        XCTAssertEqual(try String(contentsOf: realFile, encoding: .utf8), "A=1\nK=new\n")
    }

    func testSetValueThrowsForAFileThatDoesNotExist() {
        XCTAssertThrowsError(try DotEnv.setValue("new", forKey: "K", in: root.appendingPathComponent(".env")))
    }
}
