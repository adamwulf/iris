import Foundation

/// The `message:` URL that opens one message in Apple Mail.
///
/// The URL holds only the `Message-ID` header, not an account, a mailbox, or
/// a UID. Mail looks up the message ID in the messages it has downloaded, so
/// the URL opens the message only when its account is also set up in Mail.
/// When more than one copy has the same message ID (in INBOX and in Sent, or
/// under two Gmail labels), Mail opens one of them.
enum AppleMailURL {
    /// The URL for a `Message-ID` header: `message://%3Cabc@example.com%3E`
    /// for `<abc@example.com>`. Every character other than letters, digits,
    /// `-._~`, and `@` is percent-encoded. `nil` when the message ID is empty.
    static func string(forMessageID messageID: String) -> String? {
        var id = Substring(messageID.trimmingCharacters(in: .whitespaces))
        if id.hasPrefix("<"), id.hasSuffix(">") {
            id = id.dropFirst().dropLast()
        }
        guard !id.isEmpty, let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return "message://%3C\(encoded)%3E"
    }

    /// The unreserved characters of RFC 3986, and `@`.
    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@"
    )
}
