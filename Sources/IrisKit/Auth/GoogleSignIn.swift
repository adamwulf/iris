import CryptoKit
import Foundation

/// The browser sign-in of `iris auth login`, for a Google OAuth client of
/// type "Desktop app":
///
/// 1. Listen on 127.0.0.1, on a port the system picks.
/// 2. Open Google's sign-in page. It sends the browser back to
///    `http://127.0.0.1:<port>` with a code.
/// 3. Check the answer, then trade the code and the PKCE verifier for the tokens.
///
/// It returns the refresh token; the caller saves it.
public struct GoogleSignIn: Sendable {
    public static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    /// Full access to Gmail. IMAP accepts no smaller scope.
    public static let scope = "https://mail.google.com/"
    /// How long iris waits for the browser.
    public static let redirectTimeoutSeconds = 300

    private let account: GoogleSignInAccount
    private let transport: any HTTPTransport
    private let receiver: any RedirectReceiver
    private let openURL: @Sendable (URL) -> Void

    /// `openURL` opens the sign-in page in the browser. iris also logs the URL,
    /// so the user can open it by hand.
    public init(account: GoogleSignInAccount, openURL: @escaping @Sendable (URL) -> Void) {
        self.init(account: account, transport: URLSessionTransport(), receiver: LoopbackServer(), openURL: openURL)
    }

    /// A sign-in over `transport` and `receiver`. Tests pass fakes.
    init(
        account: GoogleSignInAccount,
        transport: any HTTPTransport,
        receiver: any RedirectReceiver,
        openURL: @escaping @Sendable (URL) -> Void
    ) {
        self.account = account
        self.transport = transport
        self.receiver = receiver
        self.openURL = openURL
    }

    /// Signs in and returns the refresh token.
    public func run() async throws -> String {
        let port: UInt16
        do {
            port = try await receiver.start()
        } catch {
            throw signInFailed("\(error)")
        }
        defer { receiver.stop() }

        let redirectURI = "http://127.0.0.1:\(port)"
        let pkce = PKCE.random()
        let state = OAuthRandom.string(byteCount: 16)
        guard let url = Self.authorizationURL(
            clientID: account.client.clientID,
            redirectURI: redirectURI,
            state: state,
            codeChallenge: pkce.challenge,
            loginHint: account.username
        ) else {
            throw signInFailed("iris could not build the URL of the sign-in page")
        }

        let redirect: [String: String]
        do {
            redirect = try await receiver.waitForRedirect(timeoutSeconds: Self.redirectTimeoutSeconds) {
                IrisLog.log(
                    "Opening the Google sign-in page in your browser. Sign in as \(account.username). "
                        + "If the page does not open, open this URL:\n\(url.absoluteString)",
                    fileEvent: .googleSignInStarted
                )
                openURL(url)
            }
        } catch {
            throw signInFailed("\(error)")
        }

        let code = try Self.code(fromRedirect: redirect, state: state, account: account.name)
        let tokens = try await GoogleTokenEndpoint(transport: transport).exchange(
            code: code,
            codeVerifier: pkce.verifier,
            redirectURI: redirectURI,
            client: account.client,
            account: account.name
        )
        return try Self.refreshToken(from: tokens, account: account.name)
    }

    private func signInFailed(_ reason: String) -> IrisError {
        .googleSignInFailed(account: account.name, reason: reason)
    }

    /// The sign-in page. `access_type=offline` asks for a refresh token, and
    /// `prompt=consent` makes Google send one again at every sign-in, not only
    /// the first. `login_hint` suggests the account's address.
    static func authorizationURL(
        clientID: String,
        redirectURI: String,
        state: String,
        codeChallenge: String,
        loginHint: String
    ) -> URL? {
        GoogleURL.build(authorizationEndpoint, query: [
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("response_type", "code"),
            ("scope", scope),
            ("access_type", "offline"),
            ("prompt", "consent"),
            ("state", state),
            ("code_challenge", codeChallenge),
            ("code_challenge_method", PKCE.method),
            ("login_hint", loginHint),
        ])
    }

    /// The code in the redirect's query. It checks the state first: a
    /// redirect with another state belongs to another sign-in, so even its
    /// error is not this sign-in's answer.
    static func code(fromRedirect query: [String: String], state: String, account: String) throws -> String {
        guard query["state"] == state else {
            throw IrisError.googleSignInFailed(
                account: account, reason: "the answer from the browser does not belong to this sign-in (its state differs)"
            )
        }
        if let error = query["error"] {
            let reason = error == "access_denied"
                ? "access was not allowed on the Google page (access_denied)"
                : "Google answered with the error \(error)"
            throw IrisError.googleSignInFailed(account: account, reason: reason)
        }
        guard let code = query["code"], !code.isEmpty else {
            throw IrisError.googleSignInFailed(account: account, reason: "the answer from the browser has no code")
        }
        return code
    }

    /// The refresh token in the exchange's answer. Google can leave out a
    /// scope that the user unticked on the sign-in page, and without the Gmail
    /// scope IMAP refuses the token, so that is an error here.
    static func refreshToken(from tokens: TokenResponse, account: String) throws -> String {
        if let granted = tokens.scope, !granted.split(separator: " ").contains(Substring(scope)) {
            throw IrisError.googleSignInFailed(
                account: account,
                reason: "Gmail access was not allowed (Google granted only \"\(granted)\"). "
                    + "On the Google page, allow the access to Gmail"
            )
        }
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            throw IrisError.googleNoRefreshToken(account: account)
        }
        return refreshToken
    }
}

/// PKCE (RFC 7636): the sign-in page gets the challenge, and the code
/// exchange sends the verifier, so a code that another program catches on the
/// loopback port is no use to it.
struct PKCE: Equatable {
    static let method = "S256"

    let verifier: String

    /// base64url(SHA-256(verifier)), without padding.
    var challenge: String {
        OAuthRandom.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// A new verifier: 32 random bytes as base64url, 43 characters.
    static func random() -> PKCE {
        PKCE(verifier: OAuthRandom.string(byteCount: 32))
    }
}

/// Random values for the sign-in: the PKCE verifier and the state parameter.
enum OAuthRandom {
    /// `byteCount` random bytes as base64url. `SystemRandomNumberGenerator`
    /// is cryptographically secure on Apple platforms.
    static func string(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    /// Base64 with `-` and `_` for `+` and `/`, and no `=` padding.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
