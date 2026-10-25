import Foundation

/// One HTTP request, independent of URLSession.
struct HTTPRequest: Sendable, Equatable {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Data?
}

/// One HTTP response, independent of URLSession.
struct HTTPResponse: Sendable, Equatable {
    var statusCode: Int
    var body: Data
}

/// The seam between iris and the network for Google's OAuth endpoints.
/// `URLSessionTransport` is the real one; tests use a stub, so no test
/// touches the network.
protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The real transport, over an ephemeral `URLSession`: no cookies or cache on disk.
struct URLSessionTransport: HTTPTransport {
    private let session = URLSession(configuration: .ephemeral)

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResponse(statusCode: http.statusCode, body: data)
    }
}

/// Encodes `application/x-www-form-urlencoded` bodies. Everything but letters,
/// digits, and `-._~` is percent-encoded, so `+` and `/` in a token stay what they are.
enum FormEncoder {
    /// The unreserved characters of RFC 3986, ASCII only.
    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    static func encode(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\(escape($0))=\(escape($1))" }.joined(separator: "&").utf8)
    }

    /// `text` with every character but the unreserved ones percent-encoded, as UTF-8.
    static func escape(_ text: String) -> String {
        // Only an unpaired UTF-16 surrogate makes this nil, and a Swift String has none.
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}
