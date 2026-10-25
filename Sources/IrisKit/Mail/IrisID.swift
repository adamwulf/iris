import Foundation

/// The iris ID, the one name that iris gives a message: `<account>/<mailbox>/<UID>`,
/// for example `work/INBOX/4821` or `personal/[Gmail]/All Mail/77`. Commands show a
/// message only by this name, never by its UID alone, because a UID is unique
/// only in one mailbox of one account. It is not the `Message-ID` header: iris
/// calls that header the "message ID".
///
/// The account is the text before the first `/` (an account name cannot have
/// one), the UID is the text after the last `/`, and the mailbox is all the
/// text between them, so a mailbox name can have `/` in it. The mailbox is the
/// decoded name as the caller gave it. Only INBOX is made canonical, so a
/// name typed in a different case than `iris mailboxes` shows gives a second
/// ID for the same message.
public struct IrisID: Sendable, Hashable, CustomStringConvertible {
    /// The account name, lowercased, as `iris accounts` shows it.
    public let account: String
    /// The decoded mailbox name. INBOX in any case is `INBOX`.
    public let mailbox: String
    public let uid: UInt32

    /// Account names ignore case, and so does INBOX (RFC 3501, section 5.1),
    /// so both are stored in one form: one message always gets the same ID.
    public init(account: String, mailbox: String, uid: UInt32) {
        self.account = account.lowercased()
        self.mailbox = Self.canonicalMailbox(mailbox)
        self.uid = uid
    }

    /// `mailbox` as an iris ID holds it: INBOX in any case is `INBOX`, and
    /// other names stay as they are.
    static func canonicalMailbox(_ mailbox: String) -> String {
        mailbox.lowercased() == "inbox" ? MailReader.defaultMailbox : mailbox
    }

    /// Reads `<account>/<mailbox>/<UID>`. Throws `invalidIrisID` when the
    /// account or the mailbox is empty, or the UID is not a decimal number.
    public init(parsing text: String) throws {
        guard let firstSlash = text.firstIndex(of: "/"),
              let lastSlash = text.lastIndex(of: "/"),
              firstSlash < lastSlash else {
            throw IrisError.invalidIrisID(text)
        }
        let account = text[..<firstSlash]
        let mailbox = text[text.index(after: firstSlash)..<lastSlash]
        let uidText = text[text.index(after: lastSlash)...]
        // UInt32("+5") is 5, so check the digits first.
        guard !account.isEmpty, !mailbox.isEmpty,
              !uidText.isEmpty, uidText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let uid = UInt32(uidText) else {
            throw IrisError.invalidIrisID(text)
        }
        self.init(account: String(account), mailbox: String(mailbox), uid: uid)
    }

    public var description: String {
        "\(account)/\(mailbox)/\(uid)"
    }

    /// The iris ID in single quotes, one word for a shell command line: a
    /// mailbox name can have spaces, `[ ]`, or `$`.
    var shellQuoted: String {
        MessagePage.singleQuoted(description)
    }
}

extension IrisID: Encodable {
    /// One string, the same as `description`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
