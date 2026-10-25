import Foundation
import XCTest
@testable import IrisKit

/// The redirect listener of `iris auth login`. The first test is the one test
/// that opens a socket: it binds 127.0.0.1 only and never reaches another host.
final class LoopbackServerTests: XCTestCase {
    func testTheRealListenerAnswersOn127001AndDeliversOnlyTheRedirect() async throws {
        let server = LoopbackServer()
        let port = try await server.start()
        // An early failure must not leave the listener open.
        defer { server.stop() }
        XCTAssertNotEqual(port, 0)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        let favicon = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/favicon.ico"))
        let redirect = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/?state=s&code=c"))

        // The "browser" asks for the favicon first, then follows the redirect.
        var browser: Task<(favicon: Int, redirect: Int, page: String), any Error>?
        let query = try await server.waitForRedirect(timeoutSeconds: 1) {
            browser = Task {
                let (_, faviconResponse) = try await session.data(from: favicon)
                let (page, redirectResponse) = try await session.data(from: redirect)
                return (
                    (faviconResponse as? HTTPURLResponse)?.statusCode ?? 0,
                    (redirectResponse as? HTTPURLResponse)?.statusCode ?? 0,
                    String(decoding: page, as: UTF8.self)
                )
            }
        }

        XCTAssertEqual(query, ["state": "s", "code": "c"], "the favicon request did not end the wait")
        let answers = try await XCTUnwrap(browser).value
        XCTAssertEqual(answers.favicon, 404)
        XCTAssertEqual(answers.redirect, 200)
        XCTAssertTrue(answers.page.contains("You can close this window"), answers.page)

        // The first wait's timeout (1 second) fires during this wait, and must not end it.
        do {
            _ = try await server.waitForRedirect(timeoutSeconds: 2) {}
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? LoopbackError, .timedOut(seconds: 2))
        }

        // stop() is safe to call more than once (the defer calls it a third time).
        server.stop()
        server.stop()
    }

    // MARK: - The request line

    func testQueryParametersComeFromTheRequestLine() {
        let request = "GET /?state=xyz&code=4%2F0Ab-c&scope=https://mail.google.com/ HTTP/1.1\r\nHost: 127.0.0.1:4242\r\n\r\n"
        XCTAssertEqual(LoopbackServer.queryParameters(ofRequest: request), [
            "state": "xyz", "code": "4/0Ab-c", "scope": "https://mail.google.com/",
        ])
    }

    func testQueryParametersOfAnErrorRedirect() {
        XCTAssertEqual(
            LoopbackServer.queryParameters(ofRequest: "GET /?error=access_denied&state=xyz HTTP/1.1\r\n\r\n"),
            ["error": "access_denied", "state": "xyz"]
        )
    }

    func testRequestsWithoutAQueryGiveNoParameters() {
        for request in [
            "GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n",
            "GET / HTTP/1.1\r\n\r\n",
            "",
            "not a request",
            "GET http://example.com/?code=x HTTP/1.1\r\n\r\n",
        ] {
            XCTAssertEqual(LoopbackServer.queryParameters(ofRequest: request), [:], request)
        }
    }

    // MARK: - The answer

    func testTheRedirectGetsAPageAndOtherRequestsA404() {
        let page = String(decoding: LoopbackServer.response(isRedirect: true), as: UTF8.self)
        XCTAssertTrue(page.hasPrefix("HTTP/1.1 200 OK\r\n"), page)
        XCTAssertTrue(page.contains("You can close this window"), page)
        let body = page.components(separatedBy: "\r\n\r\n").last ?? ""
        XCTAssertTrue(page.contains("Content-Length: \(body.utf8.count)\r\n"), page)

        let notFound = String(decoding: LoopbackServer.response(isRedirect: false), as: UTF8.self)
        XCTAssertEqual(
            notFound,
            "HTTP/1.1 404 Not Found\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 0\r\n"
                + "Connection: close\r\n\r\n"
        )
    }
}
