import ArgumentParser
import FellerBuncher
import Foundation
import IrisKit
import Logging

/// The executable's file sink. Use FellerBuncher's destination directly:
/// its global bootstrap would also persist SwiftMail's protocol diagnostics.
/// Defaults match graham: 10 MiB, five rotated siblings, seven-day retention.
struct IrisFileLog: Sendable {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/iris", isDirectory: true)
    }

    private let destination: FileDestination

    init(directory: URL) throws {
        destination = try FileDestination(logDirectory: directory, processName: "iris")
    }

    static func openIfPossible(
        command: any ParsableCommand,
        arguments: [String],
        directory: URL = defaultDirectory
    ) -> Self? {
        // Iris's executable leaves are async. Parser-generated help commands
        // are synchronous; Iris's groups only display help when run themselves.
        guard command is any AsyncParsableCommand,
              type(of: command).configuration.subcommands.isEmpty else { return nil }
        guard FileLogPolicy.writesFiles(arguments: arguments) else { return nil }
        do {
            return try Self(directory: directory)
        } catch {
            CLI.printToStderr("iris: file logging unavailable; check access to ~/Library/Logs/iris.")
            return nil
        }
    }

    enum CommandEvent {
        case started, completed
        case exited(Int32)
        case failed(Error)
    }

    /// There is no free-text logging API: command names come from static
    /// parser declarations, and failures contribute only fixed behavior codes.
    func record(
        _ event: CommandEvent, command: any ParsableCommand.Type,
        file: String = #fileID, function: String = #function, line: UInt = #line
    ) {
        let name = CLI.commandPath(for: command)
        let message: String
        let level: Logger.Level
        switch event {
        case .started: (message, level) = ("Starting \(name).", .notice)
        case .completed: (message, level) = ("Completed \(name).", .notice)
        case .exited(let status): (message, level) = ("\(name): exited with status \(status).", .notice)
        case .failed(let error): (message, level) = ("\(name): \(FileLogPolicy.failureCode(error)).", .error)
        }
        destination.receive(LogRecord(
            level: level, label: "iris", message: message, file: file, function: function, line: line
        ))
    }

    func record(
        _ event: IrisLog.FileEvent,
        file: String = #fileID, function: String = #function, line: UInt = #line
    ) {
        destination.receive(LogRecord(
            level: .notice, label: "iris", message: event.rawValue, file: file, function: function, line: line
        ))
    }

    func drain() async {
        await destination.drain()
    }
}
