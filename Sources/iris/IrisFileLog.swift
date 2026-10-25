import ArgumentParser
import FellerBuncher
import Foundation
import IrisKit

/// The executable's file sink. Use FellerBuncher's destination directly:
/// its global bootstrap would also persist SwiftMail's protocol diagnostics.
/// Defaults match graham: 10 MiB, five rotated siblings, seven-day retention.
struct IrisFileLog: Sendable {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/iris", isDirectory: true)
    }

    private let destination: FileDestination
    private let policy: FileLogPolicy

    init(directory: URL, settings: [String: String]) throws {
        destination = try FileDestination(logDirectory: directory, processName: "iris")
        policy = FileLogPolicy(settings: settings)
    }

    static func openIfPossible(
        command: any ParsableCommand,
        arguments: [String],
        directory: URL = defaultDirectory,
        settings: [String: String]? = nil
    ) -> Self? {
        // Iris's executable leaves are async. Parser-generated help commands
        // are synchronous; Iris's groups only display help when run themselves.
        guard command is any AsyncParsableCommand,
              type(of: command).configuration.subcommands.isEmpty else { return nil }
        guard FileLogPolicy.writesFiles(arguments: arguments) else { return nil }
        do {
            return try Self(directory: directory, settings: settings ?? AccountResolver.settings())
        } catch {
            CLI.printToStderr("iris: file logging unavailable; check access to ~/Library/Logs/iris.")
            return nil
        }
    }

    func notice(_ message: String) {
        destination.receive(LogRecord(level: .notice, label: "iris", message: policy.redacting(message)))
    }

    func failure(_ error: Error, command: String) {
        destination.receive(LogRecord(
            level: .error, label: "iris", message: policy.failure(error, command: command)
        ))
    }

    func drain() async {
        await destination.drain()
    }
}
