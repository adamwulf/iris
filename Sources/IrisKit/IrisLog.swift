import Foundation

/// The library's only way to report progress. IrisKit never prints; the
/// executable installs a handler that decides where these lines go.
public enum IrisLog {
    /// Set once at startup, before any command runs.
    nonisolated(unsafe) public static var handler: (@Sendable (String) -> Void)?

    /// Optional persistent sink. A call can give it a summary instead of
    /// interactive details, such as the URL that opens an OAuth consent page.
    /// Set once at startup, like `handler`.
    nonisolated(unsafe) public static var fileHandler: (@Sendable (String) -> Void)?

    static func log(_ message: String) {
        log(message, fileMessage: message)
    }

    static func log(_ message: String, fileMessage: String) {
        handler?(message)
        fileHandler?(fileMessage)
    }
}
