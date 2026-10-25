import Foundation

/// IrisKit never prints. The executable installs separate handlers for
/// interactive text and payload-free events suitable for persistent logs.
public enum IrisLog {
    /// Set once at startup, before any command runs.
    nonisolated(unsafe) public static var handler: (@Sendable (String) -> Void)?

    /// Only fixed behavior events may reach persistent storage. This enum
    /// deliberately has no payloads: no account, URL, key, server text, or mail
    /// content can cross this boundary. Interactive messages stay on `handler`.
    public enum FileEvent: String, Sendable {
        case googleSignInStarted = "google_sign_in_started"
        case wholeMessageFallback = "whole_message_fallback"
        case threadSearchFallback = "thread_search_fallback"
        case logoutFailed = "logout_failed"
        case readingDraftFromStdin = "reading_draft_from_stdin"
        case htmlConversionFallback = "html_conversion_fallback"
        case bodyFormatFallback = "body_format_fallback"
        case threadMessageOmitted = "thread_message_omitted"
    }

    /// Set once at startup, like `handler`.
    nonisolated(unsafe) public static var fileHandler: (@Sendable (FileEvent) -> Void)?

    static func log(_ message: String) {
        handler?(message)
    }

    static func log(_ message: String, fileEvent: FileEvent) {
        handler?(message)
        record(fileEvent)
    }

    static func record(_ event: FileEvent) {
        fileHandler?(event)
    }
}
