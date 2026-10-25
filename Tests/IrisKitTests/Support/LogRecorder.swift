import Foundation

/// Collects the lines that IrisKit logs. Set `IrisLog.handler` to `record`.
final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] { lock.withLock { recorded } }

    func record(_ line: String) {
        lock.withLock { recorded.append(line) }
    }
}
