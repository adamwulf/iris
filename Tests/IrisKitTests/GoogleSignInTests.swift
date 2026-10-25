import Foundation
import XCTest
@testable import IrisKit

/// `iris auth login`: the sign-in URL, the redirect checks, the code exchange,
/// and the whole flow over a fake receiver and a stub transport.
final class GoogleSignInTests: XCTestCase {
    private let account = GoogleSignInAccount(
        name: "personal",
        username: "me+iris@gmail.com",
        client: GoogleClient(clientID: "id.apps.googleusercontent.com", clientSecret: "client-secret")
    )

    private let tokensJSON = #"""
    {"access_token":"ya29.access","expires_in":3599,"refresh_token":"1//refresh",
     "scope":"https://mail.google.com/","token_type":"Bearer"}
    """#

    private func signInError(
        _ signIn: GoogleSignIn,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> IrisError? {
        do {
            _ = try await signIn.run()
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch {
            let irisError = error as? IrisError
            XCTAssertNotNil(irisError, "\(error) is not an IrisError", file: file, line: line)
            return irisError
        }
    }

    /// A receiver whose redirect carries `code` and the state of the page that was opened.
    private func receiver(code: String = "4/0Ab-code") -> FakeRedirectReceiver {
        FakeRedirectReceiver { url in
            ["code": code, "state": FakeRedirectReceiver.query(of: url)["state"] ?? "", "scope": GoogleSignIn.scope]
        }
    }

    // MARK: - The sign-in URL

    func testAuthorizationURLHasEveryParameter() throws {
        let url = try XCTUnwrap(GoogleSignIn.authorizationURL(
            clientID: "id.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1:4242",
            state: "state-1",
            codeChallenge: "challenge-1",
            loginHint: "me@gmail.com"
        ))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(url.path, "/o/oauth2/v2/auth")
        XCTAssertEqual(FakeRedirectReceiver.query(of: url), [
            "client_id": "id.apps.googleusercontent.com",
            "redirect_uri": "http://127.0.0.1:4242",
            "response_type": "code",
            "scope": "https://mail.google.com/",
            "access_type": "offline",
            "prompt": "consent",
            "state": "state-1",
            "code_challenge": "challenge-1",
            "code_challenge_method": "S256",
            "login_hint": "me@gmail.com",
        ])
    }

    func testAuthorizationURLEscapesPlusAndOtherDelimiters() throws {
        let url = try XCTUnwrap(GoogleSignIn.authorizationURL(
            clientID: "id", redirectURI: "http://127.0.0.1:1", state: "a&b=c", codeChallenge: "x", loginHint: "me+iris@gmail.com"
        ))
        let text = url.absoluteString
        XCTAssertTrue(text.contains("login_hint=me%2Biris%40gmail.com"), text)
        XCTAssertTrue(text.contains("state=a%26b%3Dc"), text)
        XCTAssertTrue(text.contains("scope=https%3A%2F%2Fmail.google.com%2F"), text)
        XCTAssertFalse(text.contains("+"), text)
        XCTAssertEqual(FakeRedirectReceiver.query(of: url)["login_hint"], "me+iris@gmail.com", "the value decodes back")
        XCTAssertEqual(FakeRedirectReceiver.query(of: url)["state"], "a&b=c")
    }

    func testAuthorizationURLKeepsTheParameterOrder() throws {
        let url = try XCTUnwrap(GoogleSignIn.authorizationURL(
            clientID: "id", redirectURI: "http://127.0.0.1:1", state: "s", codeChallenge: "c", loginHint: "h"
        ))
        let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name)
        XCTAssertEqual(names, [
            "client_id", "redirect_uri", "response_type", "scope", "access_type", "prompt", "state",
            "code_challenge", "code_challenge_method", "login_hint",
        ])
    }

    // MARK: - PKCE

    func testPKCEChallengeMatchesTheExampleOfRFC7636() {
        // RFC 7636, appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(PKCE.method, "S256")
    }

    func testRandomVerifiersAre43Base64URLCharactersAndDiffer() {
        let first = PKCE.random().verifier
        let second = PKCE.random().verifier
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for verifier in [first, second] {
            XCTAssertEqual(verifier.count, 43, verifier)
            XCTAssertTrue(verifier.unicodeScalars.allSatisfy(allowed.contains), verifier)
        }
        XCTAssertNotEqual(first, second)
    }

    // MARK: - The redirect

    func testCodeComesFromARedirectWithTheRightState() throws {
        XCTAssertEqual(
            try GoogleSignIn.code(fromRedirect: ["code": "4/0Ab", "state": "s1", "scope": "x"], state: "s1", account: "personal"),
            "4/0Ab"
        )
    }

    func testARedirectWithAnotherStateIsRejectedEvenWithAnError() {
        for query in [["code": "4/0Ab", "state": "other"], ["error": "access_denied", "state": "other"], ["code": "4/0Ab"]] {
            XCTAssertThrowsError(try GoogleSignIn.code(fromRedirect: query, state: "s1", account: "personal")) { error in
                guard case .googleSignInFailed(let account, let reason) = error as? IrisError else {
                    return XCTFail("unexpected error \(error)")
                }
                XCTAssertEqual(account, "personal")
                XCTAssertTrue(reason.contains("state differs"), reason)
            }
        }
    }

    func testAnErrorInTheRedirectIsReported() {
        XCTAssertThrowsError(try GoogleSignIn.code(
            fromRedirect: ["error": "access_denied", "state": "s1"], state: "s1", account: "personal"
        )) { error in
            XCTAssertEqual(error as? IrisError, .googleSignInFailed(
                account: "personal", reason: "access was not allowed on the Google page (access_denied)"
            ))
        }
        XCTAssertThrowsError(try GoogleSignIn.code(
            fromRedirect: ["error": "invalid_scope", "code": "4/0Ab", "state": "s1"], state: "s1", account: "personal"
        )) { error in
            XCTAssertEqual(error as? IrisError, .googleSignInFailed(
                account: "personal", reason: "Google answered with the error invalid_scope"
            ), "the error wins over a code")
        }
    }

    func testARedirectWithoutACodeIsRejected() {
        for query in [["state": "s1"], ["state": "s1", "code": ""]] {
            XCTAssertThrowsError(try GoogleSignIn.code(fromRedirect: query, state: "s1", account: "personal")) { error in
                XCTAssertEqual(error as? IrisError, .googleSignInFailed(
                    account: "personal", reason: "the answer from the browser has no code"
                ))
            }
        }
    }

    // MARK: - The tokens

    func testTheRefreshTokenComesFromTheExchange() throws {
        let tokens = TokenResponse(accessToken: "ya29", refreshToken: "1//refresh", scope: "openid https://mail.google.com/")
        XCTAssertEqual(try GoogleSignIn.refreshToken(from: tokens, account: "personal"), "1//refresh")
        let noScope = TokenResponse(accessToken: "ya29", refreshToken: "1//refresh", scope: nil)
        XCTAssertEqual(try GoogleSignIn.refreshToken(from: noScope, account: "personal"), "1//refresh")
    }

    func testAnExchangeWithoutARefreshTokenSaysToRemoveTheAccess() {
        for refreshToken in [nil, ""] {
            let tokens = TokenResponse(accessToken: "ya29", refreshToken: refreshToken, scope: GoogleSignIn.scope)
            XCTAssertThrowsError(try GoogleSignIn.refreshToken(from: tokens, account: "personal")) { error in
                XCTAssertEqual(error as? IrisError, .googleNoRefreshToken(account: "personal"))
            }
        }
    }

    func testAnExchangeWithoutTheGmailScopeIsRejected() {
        let tokens = TokenResponse(accessToken: "ya29", refreshToken: "1//refresh", scope: "openid")
        XCTAssertThrowsError(try GoogleSignIn.refreshToken(from: tokens, account: "personal")) { error in
            guard case .googleSignInFailed(_, let reason) = error as? IrisError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(reason.contains("Gmail access was not allowed"), reason)
        }
    }

    func testTheExchangePostsTheCodeAndTheVerifier() async throws {
        let transport = StubTransport(json: tokensJSON)
        let tokens = try await GoogleTokenEndpoint(transport: transport).exchange(
            code: "4/0Ab-code", codeVerifier: "verifier-1", redirectURI: "http://127.0.0.1:4242",
            client: account.client, account: "personal"
        )

        XCTAssertEqual(tokens, TokenResponse(accessToken: "ya29.access", refreshToken: "1//refresh", scope: GoogleSignIn.scope))
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, GoogleTokenEndpoint.url)
        XCTAssertEqual(
            StubTransport.body(of: request),
            "client_id=id.apps.googleusercontent.com&client_secret=client-secret&code=4%2F0Ab-code"
                + "&code_verifier=verifier-1&redirect_uri=http%3A%2F%2F127.0.0.1%3A4242&grant_type=authorization_code"
        )
    }

    func testAnInvalidGrantInTheExchangeIsNotAnExpiredSignIn() async {
        let transport = StubTransport(status: 400, json: #"{"error":"invalid_grant","error_description":"Bad Request"}"#)
        do {
            _ = try await GoogleTokenEndpoint(transport: transport).exchange(
                code: "4/0Ab-code", codeVerifier: "verifier-1", redirectURI: "http://127.0.0.1:4242",
                client: account.client, account: "personal"
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error as? IrisError,
                .googleTokenFailed(account: "personal", reason: "HTTP 400, invalid_grant: Bad Request")
            )
        }
    }

    func testExchangeErrorsNeverShowTheCodeTheVerifierOrTheClientSecret() async {
        let echo = "4/0Ab-code verifier-1 client-secret"
        let transport = StubTransport(status: 400, json: #"{"error":"invalid_request","error_description":"\#(echo)"}"#)
        do {
            _ = try await GoogleTokenEndpoint(transport: transport).exchange(
                code: "4/0Ab-code", codeVerifier: "verifier-1", redirectURI: "http://127.0.0.1:4242",
                client: account.client, account: "personal"
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error as? IrisError,
                .googleTokenFailed(account: "personal", reason: "HTTP 400, invalid_request: <redacted> <redacted> <redacted>")
            )
        }
    }

    // MARK: - The whole flow

    func testRunOpensThePageAfterWaitingThenExchangesTheCode() async throws {
        let console = LogRecorder()
        let file = LogRecorder()
        let previousHandler = IrisLog.handler
        let previousFileHandler = IrisLog.fileHandler
        IrisLog.handler = console.record
        IrisLog.fileHandler = file.record
        defer {
            IrisLog.handler = previousHandler
            IrisLog.fileHandler = previousFileHandler
        }
        let transport = StubTransport(json: tokensJSON)
        let receiver = receiver()
        let signIn = GoogleSignIn(account: account, transport: transport, receiver: receiver, openURL: receiver.open)

        let refreshToken = try await signIn.run()

        XCTAssertTrue(console.lines.joined().contains("https://accounts.google.com/"))
        XCTAssertEqual(file.lines, ["Opening the Google sign-in page in your browser."])
        XCTAssertEqual(refreshToken, "1//refresh")
        let events = receiver.events
        XCTAssertEqual(events.count, 4, "\(events)")
        XCTAssertEqual(events.first, .started)
        XCTAssertEqual(events.dropFirst().first, .waiting(timeoutSeconds: 300), "iris waits before it opens the page")
        XCTAssertEqual(events.last, .stopped)
        guard case .opened(let url) = events[2] else {
            return XCTFail("the page was not opened: \(events)")
        }
        let page = FakeRedirectReceiver.query(of: url)
        XCTAssertEqual(page["redirect_uri"], "http://127.0.0.1:4242")
        XCTAssertEqual(page["login_hint"], "me+iris@gmail.com")
        XCTAssertEqual(page["client_id"], "id.apps.googleusercontent.com")

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let fields = StubTransport.formFields(of: requests[0])
        XCTAssertEqual(fields["code"], "4/0Ab-code")
        XCTAssertEqual(fields["redirect_uri"], "http://127.0.0.1:4242", "the same redirect URI as the page")
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        let verifier = try XCTUnwrap(fields["code_verifier"])
        XCTAssertEqual(PKCE(verifier: verifier).challenge, page["code_challenge"], "the verifier matches the challenge")
        XCTAssertEqual(page["code_challenge_method"], "S256")
        let state = try XCTUnwrap(page["state"])
        XCTAssertGreaterThanOrEqual(state.count, 22, "the state is random: 16 bytes")
    }

    func testRunMakesANewStateAndVerifierEachTime() async throws {
        var pages: [[String: String]] = []
        for _ in 0..<2 {
            let receiver = receiver()
            let signIn = GoogleSignIn(
                account: account, transport: StubTransport(json: tokensJSON), receiver: receiver, openURL: receiver.open
            )
            _ = try await signIn.run()
            guard case .opened(let url) = receiver.events[2] else {
                return XCTFail("the page was not opened")
            }
            pages.append(FakeRedirectReceiver.query(of: url))
        }
        XCTAssertNotEqual(pages[0]["state"], pages[1]["state"])
        XCTAssertNotEqual(pages[0]["code_challenge"], pages[1]["code_challenge"])
    }

    func testRunRejectsARedirectForAnotherSignInAndSendsNoExchange() async {
        let transport = StubTransport(json: tokensJSON)
        let receiver = FakeRedirectReceiver { _ in ["code": "4/0Ab-code", "state": "forged"] }
        let error = await signInError(
            GoogleSignIn(account: account, transport: transport, receiver: receiver, openURL: receiver.open)
        )
        guard case .googleSignInFailed(_, let reason) = error else {
            return XCTFail("unexpected error \(String(describing: error))")
        }
        XCTAssertTrue(reason.contains("state differs"), reason)
        let requests = await transport.requests
        XCTAssertEqual(requests, [])
        XCTAssertEqual(receiver.events.last, .stopped, "the listener stops after an error too")
    }

    func testRunReportsATimeoutAsAFailedSignIn() async {
        let receiver = FakeRedirectReceiver { _ in throw LoopbackError.timedOut(seconds: 300) }
        let error = await signInError(
            GoogleSignIn(account: account, transport: StubTransport([]), receiver: receiver, openURL: receiver.open)
        )
        XCTAssertEqual(error, .googleSignInFailed(
            account: "personal", reason: "no answer came from the browser in 300 seconds"
        ))
        XCTAssertEqual(receiver.events.last, .stopped)
    }

    func testRunReportsAListenerThatDoesNotStart() async {
        let receiver = FakeRedirectReceiver(startError: LoopbackError.listenerFailed("POSIXErrorCode: Address already in use")) { _ in [:] }
        let error = await signInError(
            GoogleSignIn(account: account, transport: StubTransport([]), receiver: receiver, openURL: receiver.open)
        )
        XCTAssertEqual(error, .googleSignInFailed(
            account: "personal",
            reason: "iris could not listen on 127.0.0.1 for the answer from the browser "
                + "(POSIXErrorCode: Address already in use)"
        ))
        XCTAssertEqual(receiver.events, [.started], "nothing was opened")
    }

    func testRunReportsAnExchangeWithoutARefreshToken() async {
        let transport = StubTransport(json: #"{"access_token":"ya29.access","scope":"https://mail.google.com/"}"#)
        let receiver = receiver()
        let error = await signInError(
            GoogleSignIn(account: account, transport: transport, receiver: receiver, openURL: receiver.open)
        )
        XCTAssertEqual(error, .googleNoRefreshToken(account: "personal"))
    }
}
