import XCTest
@testable import IrisKit

final class OutputFormatterTests: XCTestCase {
    private struct Row: IrisRow {
        let id: String
        let name: String

        static var tableColumns: [String] { ["ID", "NAME"] }
        var tableValues: [String] { [id, name] }
        var idValue: String { id }
    }

    private let rows = [Row(id: "1", name: "first"), Row(id: "22", name: "")]

    func testTableAlignsColumnsWithoutTrailingWhitespace() throws {
        XCTAssertEqual(try OutputFormatter.render(rows, format: .table), """
        ID  NAME
        1   first
        22

        """)
    }

    func testTableKeepsAlignmentWhenTheFirstColumnIsEmpty() throws {
        XCTAssertEqual(try OutputFormatter.render([Row(id: "", name: "x")], format: .table), """
        ID  NAME
            x

        """)
    }

    func testTablePadsEmojiAndCombiningCharactersByCharacter() throws {
        let rows = [Row(id: "Lunch 🍕", name: "x"), Row(id: "Cafe\u{301}", name: "y")]
        XCTAssertEqual(
            try OutputFormatter.render(rows, format: .table),
            "ID" + String(repeating: " ", count: 7) + "NAME\n"
                + "Lunch 🍕  x\n"
                + "Cafe\u{301}" + String(repeating: " ", count: 5) + "y\n"
        )
    }

    private struct CountRow: IrisRow {
        let name: String
        let count: String

        static var tableColumns: [String] { ["NAME", "COUNT"] }
        static var rightAlignedColumns: Set<String> { ["COUNT"] }
        var tableValues: [String] { [name, count] }
        var idValue: String { name }
    }

    func testTableRightAlignsTheNamedColumnsHeaderAndValues() throws {
        let rows = [CountRow(name: "first", count: "1"), CountRow(name: "x", count: "123456"), CountRow(name: "y", count: "")]
        XCTAssertEqual(try OutputFormatter.render(rows, format: .table), """
        NAME    COUNT
        first       1
        x      123456
        y

        """)
    }

    func testJSONIsPrettyAndSorted() throws {
        XCTAssertEqual(try OutputFormatter.render([rows[0]], format: .json), """
        [
          {
            "id" : "1",
            "name" : "first"
          }
        ]

        """)
    }

    func testJSONLinesHaveOneCompactObjectPerLine() throws {
        XCTAssertEqual(try OutputFormatter.render(rows, format: .jsonl), """
        {"id":"1","name":"first"}
        {"id":"22","name":""}

        """)
    }

    func testIDPrintsOneIDPerLine() throws {
        XCTAssertEqual(try OutputFormatter.render(rows, format: .id), "1\n22\n")
    }

    // MARK: - Zero rows

    func testZeroRowsAsTableIsTheHeaderLine() throws {
        XCTAssertEqual(try OutputFormatter.render([Row](), format: .table), "ID  NAME\n")
    }

    func testZeroRowsAsJSONIsAnEmptyArray() throws {
        XCTAssertEqual(try OutputFormatter.render([Row](), format: .json), "[]\n")
    }

    func testZeroRowsAsJSONLinesIsNoText() throws {
        XCTAssertEqual(try OutputFormatter.render([Row](), format: .jsonl), "")
    }

    func testZeroRowsAsIDIsNoText() throws {
        XCTAssertEqual(try OutputFormatter.render([Row](), format: .id), "")
    }
}
