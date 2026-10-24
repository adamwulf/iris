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
    /// Renders `rows` as text. The output is deterministic: JSON keys are sorted,
    /// and table columns are two spaces apart with no trailing whitespace.
    public static func render<Row: IrisRow>(_ rows: [Row], format: OutputFormat) throws -> String {
        switch format {
        case .table:
            return table(header: Row.tableColumns, rows: rows.map(\.tableValues))
        case .json:
            return try json(rows, pretty: true)
        case .jsonl:
            return try rows.map { try json($0, pretty: false) }.joined(separator: "\n")
        case .id:
            return rows.map(\.idValue).joined(separator: "\n")
        }
    }

    static func table(header: [String], rows: [[String]]) -> String {
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
        .joined(separator: "\n")
    }

    static func json<T: Encodable>(_ value: T, pretty: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
