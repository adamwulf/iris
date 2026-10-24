import Foundation

/// How a list command prints its rows.
public enum OutputFormat: String, CaseIterable, Sendable {
    case table, json, jsonl, id
}

/// A value that list commands can print in every `OutputFormat`.
public protocol IrisRow: Encodable {
    /// The column headers for `--format table`.
    static var tableColumns: [String] { get }
    /// One value per column, in the same order as `tableColumns`.
    var tableValues: [String] { get }
    /// What `--format id` prints.
    var idValue: String { get }
}

public enum OutputFormatter {
    /// Renders `rows` as the exact text for stdout, where every line ends with
    /// `\n`. The output is deterministic: JSON keys are sorted, and table
    /// columns are two spaces apart with no trailing whitespace.
    ///
    /// Zero rows give the header line as `table` and `[]` as `json`, but no
    /// text at all as `jsonl` and `id`, so a `while read` loop gets no empty line.
    public static func render<Row: IrisRow>(_ rows: [Row], format: OutputFormat) throws -> String {
        let lines: [String]
        switch format {
        case .table:
            lines = table(header: Row.tableColumns, rows: rows.map(\.tableValues))
        case .json:
            // JSONEncoder pretty-prints an empty array as "[\n\n]".
            lines = [rows.isEmpty ? "[]" : try json(rows, pretty: true)]
        case .jsonl:
            lines = try rows.map { try json($0, pretty: false) }
        case .id:
            lines = rows.map(\.idValue)
        }
        return lines.map { $0 + "\n" }.joined()
    }

    /// The header line and one line per row, without line ends.
    static func table(header: [String], rows: [[String]]) -> [String] {
        let allRows = [header] + rows
        var widths = Array(repeating: 0, count: header.count)
        for row in allRows {
            for (index, value) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], value.count)
            }
        }
        return allRows.map { row in
            let line = row.enumerated().map { index, value in
                value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
            // Drop the padding after the last value, so no line ends in whitespace.
            return String(line.reversed().drop(while: { $0 == " " }).reversed())
        }
    }

    static func json<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
