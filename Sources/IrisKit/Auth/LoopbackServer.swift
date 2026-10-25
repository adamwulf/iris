import Foundation
import Network
import Synchronization

/// Receives the browser's redirect from Google's sign-in page.
/// `LoopbackServer` is the real one; tests use a fake.
protocol RedirectReceiver: Sendable {
    /// Starts listening on 127.0.0.1 and returns the port.
    func start() async throws -> UInt16
    /// Registers for the redirect, then calls `registered` (which opens the
    /// browser, so no redirect can come before iris waits for it), then waits
    /// for the first request with a `code` or an `error` parameter. It returns
    /// that request's query parameters, or throws after `timeoutSeconds`.
    func waitForRedirect(timeoutSeconds: Int, registered: () -> Void) async throws -> [String: String]
    /// Stops listening. Safe to call more than once.
    func stop()
}

/// Why the loopback listener gave no redirect. `GoogleSignIn` shows the text.
enum LoopbackError: Error, Equatable, CustomStringConvertible {
    case listenerFailed(String)
    case timedOut(seconds: Int)
    case stopped

    var description: String {
        switch self {
        case .listenerFailed(let reason):
            return "iris could not listen on 127.0.0.1 for the answer from the browser (\(reason))"
        case .timedOut(let seconds):
            return "no answer came from the browser in \(seconds) seconds"
        case .stopped:
            return "iris stopped listening for the answer from the browser"
        }
    }
}

/// A small HTTP listener on 127.0.0.1, on a port the system picks, for the
/// sign-in redirect `http://127.0.0.1:<port>/?code=...&state=...`. Google
/// has no copy-and-paste flow for installed apps any more, so the code must
/// come to a loopback port.
final class LoopbackServer: RedirectReceiver {
    private struct State {
        var listener: NWListener?
        var waiter: CheckedContinuation<[String: String], any Error>?
        /// Counts the waits, so the timeout of one wait never ends a later one.
        var wait = 0
    }

    private let queue = DispatchQueue(label: "iris.loopback")
    private let state = Mutex(State())

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw LoopbackError.listenerFailed(String(describing: error))
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        state.withLock { $0.listener = listener }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                switch newState {
                case .ready:
                    // A failure from now on ends the wait for the redirect.
                    listener?.stateUpdateHandler = { [weak self] laterState in
                        if case .failed(let error) = laterState {
                            self?.finish(.failure(LoopbackError.listenerFailed(String(describing: error))))
                        }
                    }
                    continuation.resume()
                case .failed(let error), .waiting(let error):
                    listener?.stateUpdateHandler = nil
                    listener?.cancel()
                    continuation.resume(throwing: LoopbackError.listenerFailed(String(describing: error)))
                case .cancelled:
                    listener?.stateUpdateHandler = nil
                    continuation.resume(throwing: LoopbackError.stopped)
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        guard let port = listener.port?.rawValue else {
            throw LoopbackError.listenerFailed("the listener has no port")
        }
        return port
    }

    func waitForRedirect(timeoutSeconds: Int, registered: () -> Void) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            let wait = state.withLock { state in
                state.waiter = continuation
                state.wait += 1
                return state.wait
            }
            queue.asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) { [weak self] in
                self?.finish(.failure(LoopbackError.timedOut(seconds: timeoutSeconds)), onlyWait: wait)
            }
            registered()
        }
    }

    func stop() {
        let listener = state.withLock { state in
            defer { state.listener = nil }
            return state.listener
        }
        listener?.cancel()
        finish(.failure(LoopbackError.stopped))
    }

    /// Answers one browser request. Only the redirect has a `code` or an
    /// `error`; the browser also asks for `/favicon.ico`, which gets a 404.
    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let query = Self.queryParameters(ofRequest: request)
            let isRedirect = query["code"] != nil || query["error"] != nil
            connection.send(content: Self.response(isRedirect: isRedirect), completion: .contentProcessed { _ in
                connection.cancel()
            })
            if isRedirect {
                self?.finish(.success(query))
            }
        }
    }

    /// Resumes the waiter once; later results are dropped. With `onlyWait`,
    /// only while that wait is still the current one.
    private func finish(_ result: Result<[String: String], any Error>, onlyWait: Int? = nil) {
        let waiter = state.withLock { state -> CheckedContinuation<[String: String], any Error>? in
            guard onlyWait == nil || onlyWait == state.wait else {
                return nil
            }
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(with: result)
    }

    /// The query parameters in the first line of an HTTP request, such as
    /// `GET /?state=xyz&code=4%2F0Ab HTTP/1.1`, decoded. Empty when the line
    /// is not a request line or its target has no query.
    static func queryParameters(ofRequest request: String) -> [String: String] {
        guard let requestLine = request.split(whereSeparator: \.isNewline).first else {
            return [:]
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3, parts[1].hasPrefix("/"), let components = URLComponents(string: String(parts[1])) else {
            return [:]
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return query
    }

    /// The whole HTTP answer: a short page for the redirect, else a 404.
    static func response(isRedirect: Bool) -> Data {
        let status = isRedirect ? "200 OK" : "404 Not Found"
        let page = isRedirect
            ? "<!doctype html><html><head><meta charset=\"utf-8\"><title>iris</title></head>"
                + "<body><p>You can close this window and go back to the terminal.</p></body></html>"
            : ""
        let head = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(page.utf8.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        return Data((head + page).utf8)
    }
}
