import Foundation

/// The one name that iris gives a message: `<account>/<mailbox>/<UID>`, for
/// example `work/INBOX/4821` or `personal/[Gmail]/All Mail/77`. Commands show a
/// message only by this name, never by its UID alone, because a UID is unique
/// only in one mailbox of one account.
///
/// The account is the text before the first `/` (an account name cannot have
/// one), the UID is the text after the last `/`, and the mailbox is all the
/// text between them, so a mailbox name can have `/` in it. The mailbox is the
/// decoded name, as `iris mailboxes` shows it.
public struct IrisID: Sendable, Hashable, CustomStringConvertible {
    /// The account name, as `iris accounts` shows it.
    public let account: String
    public let mailbox: String
    public let uid: UInt32

    public init(account: String, mailbox: String, uid: UInt32) {
        self.account = account
        self.mailbox = mailbox
        self.uid = uid
    }

    /// Reads `<account>/<mailbox>/<UID>`. Throws `invalidMessageID` when the
    /// account or the mailbox is empty, or the UID is not a decimal number.
    public init(parsing text: String) throws {
        guard let firstSlash = text.firstIndex(of: "/"),
              let lastSlash = text.lastIndex(of: "/"),
              firstSlash < lastSlash else {
            throw IrisError.invalidMessageID(text)
        }
        let account = text[..<firstSlash]
        let mailbox = text[text.index(after: firstSlash)..<lastSlash]
        let uidText = text[text.index(after: lastSlash)...]
        // UInt32("+5") is 5, so check the digits first.
        guard !account.isEmpty, !mailbox.isEmpty,
              !uidText.isEmpty, uidText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let uid = UInt32(uidText) else {
            throw IrisError.invalidMessageID(text)
        }
        self.init(account: String(account), mailbox: String(mailbox), uid: uid)
    }

    public var description: String {
        "\(account)/\(mailbox)/\(uid)"
    }
}

extension IrisID: Encodable {
    /// One string, the same as `description`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
