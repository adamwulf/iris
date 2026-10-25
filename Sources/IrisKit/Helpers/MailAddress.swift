import Foundation

/// One mailbox of an address header, such as `Jane Doe <jane@example.com>`.
/// `iris list` and `iris show` both use it, so their JSON has the same keys.
public struct MailAddress: Sendable, Equatable, Encodable {
    /// The display name, already decoded from RFC 2047, and without the quotes
    /// of a quoted-string (see `unquoted(_:)`). `nil` when the header has none,
    /// or an empty one such as `""`.
    public let name: String?
    /// The address. When the header text is not a valid address (for example
    /// `MAILER-DAEMON`), this is that text, so that nothing the sender wrote is lost.
    public let address: String

    public init(name: String?, address: String) {
        let name = name.map(Self.unquoted)
        self.name = name?.isEmpty == true ? nil : name
        self.address = address
    }

    /// The display name, else the address.
    public var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return address
    }

    /// `name` without its quotes when the whole name is one RFC 5322
    /// quoted-string, with each quoted-pair (`\"`, `\\`) unescaped. Else `name`
    /// unchanged, so quotes that are only part of a name, as in
    /// `Robert "Bob" Smith`, stay.
    ///
    /// Some servers (Zoho) keep the quotes in the ENVELOPE name, so without this
    /// `list` would show `"Doe, Jane"` where `show` shows `Doe, Jane`.
    static func unquoted(_ name: String) -> String {
        guard name.count >= 2, name.first == "\"", name.last == "\"" else {
            return name
        }
        var text = ""
        var isEscaped = false
        for character in name.dropFirst().dropLast() {
            if isEscaped {
                text.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                // The quoted-string ends before the last quote, as in `"Bob" Smith "Jr"`.
                return name
            } else {
                text.append(character)
            }
        }
        // `"Doe\"` escapes its last quote, so the quoted-string never ends.
        return isEscaped ? name : text
    }
}
