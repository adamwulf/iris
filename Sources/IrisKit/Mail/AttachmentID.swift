import Foundation

/// The attachment ID, the name that iris gives one part of a message: the
/// part's MIME section number as IMAP numbers it (RFC 3501, section 6.4.5),
/// for example `2` or `1.2`. `iris show` and `iris thread` list it first on
/// each attachment line, and `iris download` takes it after the message's
/// iris ID: an attachment ID names a part only inside one message.
public struct AttachmentID: Sendable, Hashable, CustomStringConvertible {
    /// The section numbers, outermost first, each 1 or more: `[1, 2]` for `1.2`.
    public let components: [Int]

    /// The ID of the part with these section numbers, as SwiftMail numbers
    /// the parts (its `Section`): not empty, each number 1 or more.
    init(components: [Int]) {
        self.components = components
    }

    /// Reads dot-separated numbers, each 1 or more, such as `2` or `1.2`.
    /// Throws `invalidAttachmentID` for anything else.
    public init(parsing text: String) throws {
        // Each number is an IMAP nz-number, which fits in 32 bits. UInt32("+5")
        // is 5, so check the digits first.
        let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { piece -> Int? in
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = UInt32(piece), number >= 1 else {
                return nil
            }
            return Int(number)
        }
        let components = numbers.compactMap { $0 }
        guard components.count == numbers.count else {
            throw IrisError.invalidAttachmentID(text)
        }
        self.init(components: components)
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }
}

extension AttachmentID: Encodable {
    /// One string, the same as `description`, such as `"1.2"`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
