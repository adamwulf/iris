import Foundation
import XCTest
@testable import IrisKit

/// `iris auth status`: the keys each Google account has, and one token refresh each.
final class GoogleSignInStatusTests: XCTestCase {
    private let okJSON = #"{"access_token":"ya29.access","expires_in":3599,"token_type":"Bearer"}"#

    private func ok() -> Result<HTTPResponse, any Error> {
        .success(HTTPResponse(statusCode: 200, body: Data(okJSON.utf8)))
    }

    private func googleSettings(_ name: String, refreshToken: String? = "1//refresh") -> [String: String] {
        var values = [
            "IRIS_\(name)_IMAP_HOST": "imap.gmail.com",
            "IRIS_\(name)_IMAP_USERNAME": "\(name.lowercased())@gmail.com",
            "IRIS_\(name)_GOOGLE_CLIENT_ID": "id-\(name).apps.googleusercontent.com",
            "IRIS_\(name)_GOOGLE_CLIENT_SECRET": "client-secret-\(name)",
        ]
        values["IRIS_\(name)_GOOGLE_REFRESH_TOKEN"] = refreshToken.map { "\($0)-\(name)" }
        return values
    }

    private let passwordSettings = [
        "IRIS_WORK_IMAP_HOST": "imap.zoho.com",
        "IRIS_WORK_IMAP_USERNAME": "me@example.com",
        "IRIS_WORK_IMAP_PASSWORD": "app-password",
    ]

    private func check(
        _ settings: [String: String],
        _ transport: StubTransport,
        account name: String? = nil
    ) async throws -> [GoogleSignInStatus] {
        try await GoogleSignInStatus.check(account: name, settings: settings, transport: transport)
    }

    func testEveryGoogleAccountIsCheckedWithOneRefreshAndPasswordAccountsAreLeftOut() async throws {
        let settings = googleSettings("PERSONAL").merging(googleSettings("SIDE")) { $1 }.merging(passwordSettings) { $1 }
        let transport = StubTransport([ok(), ok()])

        let statuses = try await check(settings, transport)

        XCTAssertEqual(statuses, [
            GoogleSignInStatus(
                name: "personal", username: "personal@gmail.com",
                clientIDSet: true, clientSecretSet: true, refreshTokenSet: true, problem: nil
            ),
            GoogleSignInStatus(
                name: "side", username: "side@gmail.com",
                clientIDSet: true, clientSecretSet: true, refreshTokenSet: true, problem: nil
            ),
        ])
        XCTAssertTrue(statuses.allSatisfy(\.signedIn))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { StubTransport.formFields(of: $0)["refresh_token"] }, [
            "1//refresh-PERSONAL", "1//refresh-SIDE",
        ])
    }

    func testAnExpiredSignInGoesInItsRowAndDoesNotHideTheOthers() async throws {
        let settings = googleSettings("OLD").merging(googleSettings("PERSONAL")) { $1 }
        let expired = HTTPResponse(statusCode: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
        let transport = StubTransport([.success(expired), ok()])

        let statuses = try await check(settings, transport)

        XCTAssertEqual(statuses.map(\.name), ["old", "personal"])
        XCTAssertEqual(statuses[0].problem, IrisError.googleSignInExpired(account: "old").errorDescription)
        XCTAssertFalse(statuses[0].signedIn)
        XCTAssertTrue(statuses[0].problem?.contains("`iris auth login --account old`") ?? false)
        XCTAssertNil(statuses[1].problem)
        XCTAssertTrue(statuses[1].signedIn)
    }

    func testAnAccountWithoutARefreshTokenIsNotSignedInAndSendsNoRequest() async throws {
        let transport = StubTransport([])
        let statuses = try await check(googleSettings("NEW", refreshToken: nil), transport)

        XCTAssertEqual(statuses, [GoogleSignInStatus(
            name: "new", username: "new@gmail.com", clientIDSet: true, clientSecretSet: true, refreshTokenSet: false,
            problem: IrisError.googleNotSignedIn(account: "new").errorDescription
        )])
        let requests = await transport.requests
        XCTAssertEqual(requests, [])
    }

    func testMissingAndConflictingKeysGoInTheRowWithoutARequest() async throws {
        var settings = googleSettings("HALF")
        settings["IRIS_HALF_GOOGLE_CLIENT_SECRET"] = nil
        settings.merge(googleSettings("BOTH")) { $1 }
        settings["IRIS_BOTH_IMAP_PASSWORD"] = "app-password"
        let transport = StubTransport([])

        let statuses = try await check(settings, transport)

        XCTAssertEqual(statuses.map(\.name), ["both", "half"])
        let conflict = try XCTUnwrap(statuses[0].problem)
        XCTAssertTrue(conflict.contains("Use one or the other"), conflict)
        XCTAssertEqual(statuses[1].problem, IrisError.missingSetting(key: "IRIS_HALF_GOOGLE_CLIENT_SECRET").errorDescription)
        XCTAssertFalse(statuses[1].clientSecretSet)
        let requests = await transport.requests
        XCTAssertEqual(requests, [])
    }

    func testOneNamedAccountIsCheckedAlone() async throws {
        let settings = googleSettings("PERSONAL").merging(googleSettings("SIDE")) { $1 }
        let transport = StubTransport([ok()])

        let statuses = try await check(settings, transport, account: "Side")

        XCTAssertEqual(statuses.map(\.name), ["side"])
        XCTAssertTrue(statuses[0].signedIn)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testANamedPasswordAccountSaysItDoesNotSignInWithGoogle() async throws {
        let transport = StubTransport([])
        let statuses = try await check(passwordSettings, transport, account: "work")

        XCTAssertEqual(statuses, [GoogleSignInStatus(
            name: "work", username: "me@example.com", clientIDSet: false, clientSecretSet: false, refreshTokenSet: false,
            problem: "IRIS_WORK_GOOGLE_CLIENT_ID is not set, so the account logs in with a password, not with Google"
        )])
        let requests = await transport.requests
        XCTAssertEqual(requests, [])
    }

    func testAnUnknownAccountOrNoGoogleAccountIsAnError() async {
        for (name, settings, expected) in [
            ("nope", googleSettings("PERSONAL"), IrisError.unknownAccount(name: "nope", available: ["personal"])),
            (nil, passwordSettings, IrisError.noGoogleAccounts),
            (nil, [:], IrisError.noAccountsConfigured),
        ] as [(String?, [String: String], IrisError)] {
            do {
                _ = try await check(settings, StubTransport([]), account: name)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? IrisError, expected)
            }
        }
    }

    func testNoGoogleAccountsNamesTheKeysAndTheLoginCommand() throws {
        let message = try XCTUnwrap(IrisError.noGoogleAccounts.errorDescription)
        XCTAssertTrue(message.contains("IRIS_NAME_GOOGLE_CLIENT_ID"), message)
        XCTAssertTrue(message.contains("IRIS_NAME_GOOGLE_CLIENT_SECRET"), message)
        XCTAssertTrue(message.contains("`iris auth login --account <name>`"), message)
    }

    func testNoOutputEverShowsASecret() async throws {
        // Each of Google's answers echoes the secrets that its request sent.
        let personal = "client-secret-PERSONAL 1//refresh-PERSONAL"
        let side = "client-secret-SIDE 1//refresh-SIDE"
        let settings = googleSettings("PERSONAL").merging(googleSettings("SIDE")) { $1 }
        let transport = StubTransport([
            .success(HTTPResponse(statusCode: 401, body: Data(#"{"error":"invalid_client","error_description":"\#(personal)"}"#.utf8))),
            .success(HTTPResponse(statusCode: 500, body: Data(side.utf8))),
        ])

        let statuses = try await check(settings, transport)

        XCTAssertTrue(statuses.allSatisfy { $0.problem?.contains("<redacted>") ?? false }, "\(statuses)")
        for format in [OutputFormat.table, .json, .jsonl, .id] {
            let output = try OutputFormatter.render(statuses, format: format)
            for secret in ["client-secret-PERSONAL", "1//refresh-PERSONAL", "client-secret-SIDE", "1//refresh-SIDE", "ya29"] {
                XCTAssertFalse(output.contains(secret), "\(secret) in \(format): \(output)")
            }
        }
    }

    func testTheTableSaysSetOrMissingAndOk() throws {
        let rows = [
            GoogleSignInStatus(
                name: "personal", username: "me@gmail.com",
                clientIDSet: true, clientSecretSet: true, refreshTokenSet: true, problem: nil
            ),
            GoogleSignInStatus(
                name: "new", username: nil,
                clientIDSet: true, clientSecretSet: false, refreshTokenSet: false, problem: "not yet"
            ),
        ]
        XCTAssertEqual(try OutputFormatter.render(rows, format: .table), """
        NAME      USERNAME      CLIENT ID  CLIENT SECRET  REFRESH TOKEN  STATUS
        personal  me@gmail.com  set        set            set            ok
        new                     set        missing        missing        not yet

        """)
        XCTAssertEqual(try OutputFormatter.render([rows[1]], format: .jsonl), #"""
        {"clientIDSet":true,"clientSecretSet":false,"name":"new","problem":"not yet","refreshTokenSet":false,"signedIn":false}

        """#)
        XCTAssertEqual(try OutputFormatter.render(rows, format: .id), "personal\nnew\n")
    }
}
