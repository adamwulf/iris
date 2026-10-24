import Foundation

/// IMAP's modified UTF-7 (RFC 3501, section 5.1.3): the form a mailbox name has
/// on the wire. SwiftMail keeps that form, and the codec in NIOIMAPCore is
/// internal, so iris has its own.
///
/// Printable ASCII stands for itself, except `&`, which is `&-`. Every other run
/// of characters is `&`, the base64 of its UTF-16BE code units (with `,` for `/`
/// and no `=` padding), and `-`. So `R&D` is `R&-D`, and `Entwürfe` is `Entw&APw-rfe`.
enum ModifiedUTF7 {
    /// The wire form of `name`.
    static func encode(_ name: String) -> String {
        var result = ""
        var run: [UInt16] = []
        func endRun() {
            guard !run.isEmpty else {
                return
            }
            let bytes = run.flatMap { [UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0)] }
            let base64 = Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "/", with: ",")
                .replacingOccurrences(of: "=", with: "")
            result += "&" + base64 + "-"
            run = []
        }
        for scalar in name.unicodeScalars {
            if isPrintableASCII(scalar) {
                endRun()
                result.unicodeScalars.append(scalar)
                if scalar == "&" {
                    result += "-"
                }
            } else {
                run += scalar.utf16
            }
        }
        endRun()
        return result
    }

    /// The name that `wireName` stands for, or `wireName` unchanged when it is
    /// not valid modified UTF-7. Only the form that `encode` gives is valid (RFC
    /// 3501 allows no other), so for every valid wire name, typing the decoded
    /// name reaches the same mailbox. An invalid one, such as a raw `R&D` from a
    /// server that does not follow RFC 3501, encodes to a different wire name.
    static func decode(_ wireName: String) -> String {
        guard let name = decodedRuns(wireName), encode(name) == wireName else {
            return wireName
        }
        return name
    }

    /// `wireName` with each `&...-` run decoded, or nil when a run is not
    /// closed or is not base64 of whole UTF-16 code units.
    private static func decodedRuns(_ wireName: String) -> String? {
        var result = ""
        var rest = wireName.unicodeScalars[...]
        while let scalar = rest.popFirst() {
            guard scalar == "&" else {
                result.unicodeScalars.append(scalar)
                continue
            }
            guard let end = rest.firstIndex(of: "-") else {
                return nil
            }
            let base64 = String(rest[..<end])
            rest = rest[rest.index(after: end)...]
            if base64.isEmpty {
                result += "&"
                continue
            }
            let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let data = Data(base64Encoded: base64.replacingOccurrences(of: ",", with: "/") + padding),
                  data.count % 2 == 0 else {
                return nil
            }
            let bytes = [UInt8](data)
            let units = stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
            // A lone surrogate decodes to U+FFFD, whose encoding is not the wire
            // name, so `decode` rejects it.
            result += String(decoding: units, as: UTF16.self)
        }
        return result
    }

    private static func isPrintableASCII(_ scalar: Unicode.Scalar) -> Bool {
        (0x20...0x7E).contains(scalar.value)
    }
}
