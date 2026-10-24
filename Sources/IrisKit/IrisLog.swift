import Foundation

/// The library's only way to report progress. IrisKit never prints; the
/// executable installs a handler that decides where these lines go.
public enum IrisLog {
    /// Set once at startup, before any command runs.
    nonisolated(unsafe) public static var handler: (@Sendable (String) -> Void)?

    static func log(_ message: String) {
        handler?(message)
    }
}
