import Foundation

/// Google's OAuth token endpoint. It turns a refresh token into an access
/// token before each IMAP session, and the code from the sign-in page into
/// the first tokens during `iris auth login`.
struct GoogleTokenEndpoint: Sendable {
    static let url = URL(string: "https://oauth2.googleapis.com/token")!

    /// Which grant a request sends. Google answers `invalid_grant` to both,
    /// but only for a refresh token does it mean that the sign-in expired.
    enum Grant: Sendable {
        case refreshToken
        case authorizationCode
    }

    let transport: any HTTPTransport

    /// A new access token. iris keeps no cache: one IMAP session needs one token.
    func accessToken(client: GoogleClient, refreshToken: String, account: String) async throws -> String {
        let tokens = try await post(
            [
                ("client_id", client.clientID),
                ("client_secret", client.clientSecret),
                ("refresh_token", refreshToken),
                ("grant_type", "refresh_token"),
            ],
            grant: .refreshToken,
            secrets: [client.clientSecret, refreshToken],
            account: account
        )
        return tokens.accessToken
    }

    /// The tokens for the code that the sign-in page sent to `redirectURI`.
    /// `codeVerifier` proves that this is the program that opened the page (PKCE).
    func exchange(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        client: GoogleClient,
        account: String
    ) async throws -> TokenResponse {
        try await post(
            [
                ("client_id", client.clientID),
                ("client_secret", client.clientSecret),
                ("code", code),
                ("code_verifier", codeVerifier),
                ("redirect_uri", redirectURI),
                ("grant_type", "authorization_code"),
            ],
            grant: .authorizationCode,
            secrets: [client.clientSecret, code, codeVerifier],
            account: account
        )
    }

    /// Sends one form POST. `secrets` are the values it sends that no error may show.
    private func post(
        _ fields: [(String, String)],
        grant: Grant,
        secrets: [String],
        account: String
    ) async throws -> TokenResponse {
        let request = HTTPRequest(
            method: "POST",
            url: Self.url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: FormEncoder.encode(fields)
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            let reason = (error as? URLError)?.localizedDescription ?? String(describing: error)
            throw IrisError.googleTokenFailed(account: account, reason: Redaction.redacting(secrets, in: reason))
        }
        return try Self.tokens(from: response, grant: grant, secrets: secrets, account: account)
    }

    /// The tokens in an answer, or the `IrisError` that the answer means.
    static func tokens(
        from response: HTTPResponse,
        grant: Grant,
        secrets: [String],
        account: String
    ) throws -> TokenResponse {
        guard (200..<300).contains(response.statusCode) else {
            throw error(for: response, grant: grant, secrets: secrets, account: account)
        }
        guard let tokens = try? JSONDecoder().decode(TokenResponse.self, from: response.body) else {
            throw IrisError.googleTokenFailed(
                account: account, reason: "Google answered HTTP \(response.statusCode) without an access token"
            )
        }
        return tokens
    }

    /// The error for an answer that is not 2xx. Google's error answers are
    /// JSON, such as `{"error": "invalid_grant", "error_description": "Bad Request"}`.
    static func error(for response: HTTPResponse, grant: Grant, secrets: [String], account: String) -> IrisError {
        let answer = try? JSONDecoder().decode(TokenErrorResponse.self, from: response.body)
        var reason = "HTTP \(response.statusCode)"
        if let code = answer?.error {
            reason += ", \(code)"
            if let description = answer?.errorDescription {
                reason += ": \(description)"
            }
        } else {
            // Not Google's JSON, such as a proxy's HTML page: show the start of it on one line.
            let text = String(decoding: response.body, as: UTF8.self)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            if !text.isEmpty {
                reason += ": " + String(text.prefix(200))
            }
        }
        let redacted = Redaction.redacting(secrets, in: reason)
        switch (response.statusCode, answer?.error, grant) {
        case (400, "invalid_grant", .refreshToken):
            return .googleSignInExpired(account: account)
        case (_, "invalid_client", _), (_, "unauthorized_client", _):
            return .googleClientRejected(account: account, reason: redacted)
        default:
            return .googleTokenFailed(account: account, reason: redacted)
        }
    }
}

/// A successful answer from the token endpoint. A refresh gives only an
/// access token; the first sign-in also gives a refresh token.
struct TokenResponse: Decodable, Equatable {
    let accessToken: String
    let refreshToken: String?
    /// The granted scopes, separated by spaces.
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// An error answer from the token endpoint (RFC 6749, section 5.2).
struct TokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
