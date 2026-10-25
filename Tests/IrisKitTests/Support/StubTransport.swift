import Foundation
@testable import IrisKit

/// An `HTTPTransport` with scripted answers, served in order. It records every
/// request, so tests can check what iris sent. A request with no answer left
/// gets HTTP 599, so a test fails loudly instead of touching the network.
actor StubTransport: HTTPTransport {
    private var answers: [Result<HTTPResponse, any Error>]
    private(set) var requests: [HTTPRequest] = []

    init(_ answers: [Result<HTTPResponse, any Error>]) {
        self.answers = answers
    }

    /// A transport whose one answer is `json` with `status`.
    init(status: Int = 200, json: String) {
        self.init([.success(HTTPResponse(statusCode: status, body: Data(json.utf8)))])
    }

    /// A transport whose one answer is `error`, as a network failure.
    init(error: any Error) {
        self.init([.failure(error)])
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !answers.isEmpty else {
            return HTTPResponse(statusCode: 599, body: Data("no answer scripted for \(request.url)".utf8))
        }
        return try answers.removeFirst().get()
    }

    /// The body of `request` as text.
    static func body(of request: HTTPRequest) -> String {
        request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// The decoded fields of a form body, `a=1&b=2`.
    static func formFields(of request: HTTPRequest) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in body(of: request).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? "" }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }
}
