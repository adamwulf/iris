import Foundation
import XCTest
@testable import IrisKit

/// The token refresh that runs before each IMAP session of a Google account.
final class GoogleTokenEndpointTests: XCTestCase {
    private let client = GoogleClient(clientID: "id.apps.googleusercontent.com", clientSecret: "client-secret")
    private let refreshToken = "1//refresh-token"

    private func refresh(with transport: StubTransport) async throws -> String {
        try await GoogleTokenEndpoint(transport: transport)
            .accessToken(client: client, refreshToken: refreshToken, account: "personal")
    }

    /// The error that a refresh throws with `transport`.
    private func refreshError(
        with transport: StubTransport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> IrisError? {
        do {
            _ = try await refresh(with: transport)
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch {
            let irisError = error as? IrisError
            XCTAssertNotNil(irisError, "\(error) is not an IrisError", file: file, line: line)
            return irisError
        }
    }

    func testRefreshPostsTheExactFormBody() async throws {
        let transport = StubTransport(json: #"{"access_token":"ya29.access","expires_in":3599,"token_type":"Bearer"}"#)

        _ = try await refresh(with: transport)

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(request.headers, ["Content-Type": "application/x-www-form-urlencoded"])
        XCTAssertEqual(
            StubTransport.body(of: request),
            "client_id=id.apps.googleusercontent.com&client_secret=client-secret"
                + "&refresh_token=1%2F%2Frefresh-token&grant_type=refresh_token"
        )
    }

    func testRefreshReturnsTheAccessToken() async throws {
        let transport = StubTransport(json: #"{"access_token":"ya29.access","expires_in":3599,"scope":"https://mail.google.com/"}"#)
        let accessToken = try await refresh(with: transport)
        XCTAssertEqual(accessToken, "ya29.access")
    }

    func testInvalidGrantMeansTheSignInExpired() async {
        let transport = StubTransport(
            status: 400, json: #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#
        )
        let error = await refreshError(with: transport)
        XCTAssertEqual(error, .googleSignInExpired(account: "personal"))
    }

    func testInvalidClientPointsAtTheClientKeys() async {
        let transport = StubTransport(
            status: 401, json: #"{"error":"invalid_client","error_description":"The OAuth client was not found."}"#
        )
        let error = await refreshError(with: transport)
        XCTAssertEqual(
            error,
            .googleClientRejected(account: "personal", reason: "HTTP 401, invalid_client: The OAuth client was not found.")
        )
    }

    func testADeletedClientAlsoPointsAtTheClientKeys() async {
        // Google answers this after the OAuth client, or its Cloud project, was deleted.
        let transport = StubTransport(
            status: 401, json: #"{"error":"deleted_client","error_description":"The OAuth client was deleted."}"#
        )
        let error = await refreshError(with: transport)
        XCTAssertEqual(
            error,
            .googleClientRejected(account: "personal", reason: "HTTP 401, deleted_client: The OAuth client was deleted.")
        )
    }

    func testUnauthorizedClientAlsoPointsAtTheClientKeys() async {
        let transport = StubTransport(status: 400, json: #"{"error":"unauthorized_client"}"#)
        let error = await refreshError(with: transport)
        XCTAssertEqual(error, .googleClientRejected(account: "personal", reason: "HTTP 400, unauthorized_client"))
    }

    func testAnotherStatusShowsTheStartOfTheAnswerOnOneLine() async {
        let transport = StubTransport(status: 503, json: "<html>\n  <body>Service Unavailable</body>\n</html>\n")
        let error = await refreshError(with: transport)
        XCTAssertEqual(
            error,
            .googleTokenFailed(account: "personal", reason: "HTTP 503: <html> <body>Service Unavailable</body> </html>")
        )
    }

    func testAnotherErrorCodeIsATokenFailure() async {
        let transport = StubTransport(status: 400, json: #"{"error":"invalid_request","error_description":"Missing parameter"}"#)
        let error = await refreshError(with: transport)
        XCTAssertEqual(
            error,
            .googleTokenFailed(account: "personal", reason: "HTTP 400, invalid_request: Missing parameter")
        )
    }

    func testAnAnswerWithoutAnAccessTokenIsATokenFailure() async {
        let transport = StubTransport(json: #"{"token_type":"Bearer"}"#)
        let error = await refreshError(with: transport)
        XCTAssertEqual(
            error,
            .googleTokenFailed(account: "personal", reason: "Google answered HTTP 200 without an access token")
        )
    }

    func testANetworkFailureIsATokenFailure() async {
        let offline = URLError(.notConnectedToInternet)
        let error = await refreshError(with: StubTransport(error: offline))
        XCTAssertEqual(error, .googleTokenFailed(account: "personal", reason: offline.localizedDescription))
    }

    func testNoErrorShowsTheClientSecretOrTheRefreshToken() async {
        let echo = "client-secret 1//refresh-token"
        let transports = [
            StubTransport(status: 401, json: #"{"error":"invalid_client","error_description":"\#(echo)"}"#),
            StubTransport(status: 400, json: #"{"error":"invalid_request","error_description":"\#(echo)"}"#),
            StubTransport(status: 500, json: echo),
            StubTransport(error: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: echo])),
        ]
        for transport in transports {
            let message = await refreshError(with: transport)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("<redacted> <redacted>"), message)
            XCTAssertFalse(message.contains("client-secret"), message)
            XCTAssertFalse(message.contains("1//refresh-token"), message)
        }
    }

    func testFormEncoderEscapesEverythingButUnreservedASCII() {
        XCTAssertEqual(
            String(decoding: FormEncoder.encode([("a b", "x+y/z=é~._-")]), as: UTF8.self),
            "a%20b=x%2By%2Fz%3D%C3%A9~._-"
        )
    }
}
