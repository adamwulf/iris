import Foundation

/// Removes secrets from text that iris shows, such as a server's answer, an
/// answer from Google's token endpoint, or a network error.
enum Redaction {
    static let placeholder = "<redacted>"

    /// `text` with every copy of each secret replaced by `<redacted>`, in case
    /// a server repeats one. Empty secrets are skipped. Longer secrets go
    /// first, so a secret that contains another one is removed whole.
    static func redacting(_ secrets: [String], in text: String) -> String {
        secrets
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .reduce(text) { text, secret in text.replacingOccurrences(of: secret, with: placeholder) }
    }
}
