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
