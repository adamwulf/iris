import Foundation

/// One mailbox of an address header, such as `Jane Doe <jane@example.com>`.
/// `iris list` and `iris show` both use it, so their JSON has the same keys.
public struct MailAddress: Sendable, Equatable, Encodable {
    /// The display name, already decoded from RFC 2047. `nil` when the header has none.
    public let name: String?
    /// The address. When the header text is not a valid address (for example
    /// `MAILER-DAEMON`), this is that text, so that nothing the sender wrote is lost.
    public let address: String

    public init(name: String?, address: String) {
        self.name = name
        self.address = address
    }

    /// The display name, else the address.
    public var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return address
    }
}
