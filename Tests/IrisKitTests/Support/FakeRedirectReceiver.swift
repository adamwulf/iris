import Foundation
import Synchronization
@testable import IrisKit

/// A `RedirectReceiver` with no listener. Pass its `open` as the sign-in's
/// browser opener: `waitForRedirect` answers with `respond(openedURL)`, so a
/// test can echo the state of the page that was opened. It records every
/// step, so a test can check the order.
final class FakeRedirectReceiver: RedirectReceiver {
    enum Event: Equatable {
        case started
        case waiting(timeoutSeconds: Int)
        case opened(URL)
        case stopped
    }

    private let port: UInt16
    private let startError: (any Error)?
    private let respond: @Sendable (URL) throws -> [String: String]
    private let state = Mutex<(events: [Event], opened: URL?)>(([], nil))

    init(
        port: UInt16 = 4242,
        startError: (any Error)? = nil,
        respond: @escaping @Sendable (URL) throws -> [String: String]
    ) {
        self.port = port
        self.startError = startError
        self.respond = respond
    }

    var events: [Event] {
        state.withLock { $0.events }
    }

    /// The browser opener to pass to `GoogleSignIn`.
    var open: @Sendable (URL) -> Void {
        { [self] url in
            state.withLock {
                $0.events.append(.opened(url))
                $0.opened = url
            }
        }
    }

    func start() async throws -> UInt16 {
        state.withLock { $0.events.append(.started) }
        if let startError {
            throw startError
        }
        return port
    }

    func waitForRedirect(timeoutSeconds: Int, registered: () -> Void) async throws -> [String: String] {
        state.withLock { $0.events.append(.waiting(timeoutSeconds: timeoutSeconds)) }
        registered()
        guard let url = state.withLock({ $0.opened }) else {
            throw LoopbackError.timedOut(seconds: timeoutSeconds)
        }
        return try respond(url)
    }

    func stop() {
        state.withLock { $0.events.append(.stopped) }
    }

    /// The decoded query parameters of `url`.
    static func query(of url: URL) -> [String: String] {
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return query
    }
}
