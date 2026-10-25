import Foundation
import XCTest
@testable import IrisKit

final class AccountResolverTests: XCTestCase {
    private func settings(_ name: String, host: String = "imap.example.com", port: String? = nil) -> [String: String] {
        var values = [
            "IRIS_\(name)_IMAP_HOST": host,
            "IRIS_\(name)_IMAP_USERNAME": "\(name.lowercased())@example.com",
            "IRIS_\(name)_IMAP_PASSWORD": "secret-\(name)",
        ]
        values["IRIS_\(name)_IMAP_PORT"] = port
        return values
    }

    func testKeyUppercasesTheAccountName() {
        XCTAssertEqual(AccountResolver.key(.host, account: "work"), "IRIS_WORK_IMAP_HOST")
        XCTAssertEqual(AccountResolver.key(.password, account: "My_Gmail2"), "IRIS_MY_GMAIL2_IMAP_PASSWORD")
    }

    func testAccountNameFromKeyAllowsUnderscoresAndDigits() {
        XCTAssertEqual(AccountResolver.accountName(fromKey: "IRIS_WORK_IMAP_HOST"), "work")
        XCTAssertEqual(AccountResolver.accountName(fromKey: "IRIS_MY_GMAIL_2_IMAP_PASSWORD"), "my_gmail_2")
        XCTAssertEqual(AccountResolver.accountName(fromKey: "IRIS_DEFAULT_IMAP_PORT"), "default")
    }

    func testAccountNameFromKeyRejectsOtherKeys() {
        XCTAssertNil(AccountResolver.accountName(fromKey: "IRIS_DEFAULT_ACCOUNT"))
        XCTAssertNil(AccountResolver.accountName(fromKey: "IRIS_IMAP_HOST"))
        XCTAssertNil(AccountResolver.accountName(fromKey: "IRIS__IMAP_HOST"), "an empty name is not an account")
        XCTAssertNil(AccountResolver.accountName(fromKey: "IRIS_work_IMAP_HOST"), "keys use uppercase names")
        XCTAssertNil(AccountResolver.accountName(fromKey: "IRIS_MY-GMAIL_IMAP_HOST"))
        XCTAssertNil(AccountResolver.accountName(fromKey: "GOOGLE_CLIENT_ID"))
    }

    func testAccountNamesAreSortedAndIncludeIncompleteAccounts() {
        var values = settings("WORK").merging(settings("PERSONAL")) { $1 }
        values["IRIS_HALF_IMAP_HOST"] = "imap.example.com"
        values["UNRELATED"] = "x"
        XCTAssertEqual(AccountResolver.accountNames(in: values), ["half", "personal", "work"])
    }

    func testSettingsLetTheEnvironmentWinAndIgnoreEmptyEnvironmentValues() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "IRIS_WORK_IMAP_HOST=from-file\nIRIS_WORK_IMAP_USERNAME=file-user".write(
            to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let values = AccountResolver.settings(
            environment: ["IRIS_WORK_IMAP_HOST": "from-env", "IRIS_WORK_IMAP_USERNAME": ""],
            startingIn: dir
        )

        XCTAssertEqual(values["IRIS_WORK_IMAP_HOST"], "from-env")
        XCTAssertEqual(values["IRIS_WORK_IMAP_USERNAME"], "file-user")
    }

    func testResolveUsesTheOnlyAccountWhenNoNameIsGiven() throws {
        let account = try AccountResolver.resolve(name: nil, settings: settings("WORK", port: "1993"))
        XCTAssertEqual(account, Account(
            name: "work", host: "imap.example.com", port: 1993,
            username: "work@example.com", authentication: .password("secret-WORK")
        ))
    }

    func testResolveDefaultsThePortTo993() throws {
        XCTAssertEqual(try AccountResolver.resolve(name: nil, settings: settings("WORK")).port, 993)
    }

    func testResolveMatchesTheNameInAnyCase() throws {
        let values = settings("WORK").merging(settings("PERSONAL")) { $1 }
        XCTAssertEqual(try AccountResolver.resolve(name: "Personal", settings: values).name, "personal")
    }

    func testResolveUsesTheDefaultAccountKeyWhenSeveralExist() throws {
        var values = settings("WORK").merging(settings("PERSONAL")) { $1 }
        values[AccountResolver.defaultAccountKey] = "Work"
        XCTAssertEqual(try AccountResolver.resolve(name: nil, settings: values).name, "work")
        XCTAssertEqual(try AccountResolver.resolve(name: "personal", settings: values).name, "personal",
                       "--account wins over the default")
    }

    func testResolveThrowsWhenSeveralAccountsExistAndNoneIsChosen() {
        let values = settings("WORK").merging(settings("PERSONAL")) { $1 }
        XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: values)) { error in
            XCTAssertEqual(error as? IrisError, .accountNotChosen(available: ["personal", "work"]))
        }
    }

    func testResolveThrowsForAnUnknownName() {
        XCTAssertThrowsError(try AccountResolver.resolve(name: "nope", settings: settings("WORK"))) { error in
            XCTAssertEqual(error as? IrisError, .unknownAccount(name: "nope", available: ["work"]))
        }
    }

    func testResolveThrowsWhenTheDefaultAccountKeyNamesAnUnknownAccount() {
        var values = settings("WORK")
        values[AccountResolver.defaultAccountKey] = "nope"
        XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: values)) { error in
            guard case .invalidSetting(let key, _) = error as? IrisError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(key, AccountResolver.defaultAccountKey)
        }
    }

    func testResolveThrowsWhenNoAccountsExist() {
        XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: ["OTHER": "x"])) { error in
            XCTAssertEqual(error as? IrisError, .noAccountsConfigured)
        }
    }

    func testResolveThrowsForAMissingRequiredSetting() {
        var values = settings("WORK")
        values["IRIS_WORK_IMAP_PASSWORD"] = nil
        XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: values)) { error in
            XCTAssertEqual(error as? IrisError, .missingSetting(key: "IRIS_WORK_IMAP_PASSWORD"))
        }
    }

    func testResolveThrowsForABadPort() {
        for bad in ["abc", "0", "65536"] {
            XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: settings("WORK", port: bad))) { error in
                guard case .invalidSetting(let key, _) = error as? IrisError else {
                    return XCTFail("unexpected error \(error) for port \(bad)")
                }
                XCTAssertEqual(key, "IRIS_WORK_IMAP_PORT")
            }
        }
    }

    func testSummariesReportProblemsAndNeverIncludeThePassword() throws {
        var values = settings("WORK")
        values["IRIS_HALF_IMAP_HOST"] = "imap.half.com"
        values["IRIS_HALF_IMAP_PORT"] = "nope"
        values[AccountResolver.defaultAccountKey] = "work"

        let summaries = try AccountResolver.summaries(in: values)

        XCTAssertEqual(summaries, [
            AccountSummary(
                name: "half", isDefault: false, username: nil, host: "imap.half.com", port: nil,
                problems: [
                    "missing IRIS_HALF_IMAP_USERNAME",
                    "missing IRIS_HALF_IMAP_PASSWORD",
                    "IRIS_HALF_IMAP_PORT is not a port number",
                ]
            ),
            AccountSummary(
                name: "work", isDefault: true, username: "work@example.com", host: "imap.example.com",
                port: 993, problems: []
            ),
        ])
        let json = try OutputFormatter.render(summaries, format: .json)
        XCTAssertFalse(json.contains("secret"))
    }

    func testSummariesThrowWhenNoAccountsExist() {
        XCTAssertThrowsError(try AccountResolver.summaries(in: ["OTHER": "x"])) { error in
            XCTAssertEqual(error as? IrisError, .noAccountsConfigured)
        }
    }

    func testDefaultAccountErrorReportsAnUnknownName() {
        var values = settings("WORK").merging(settings("PERSONAL")) { $1 }
        values[AccountResolver.defaultAccountKey] = "Wrok"

        XCTAssertEqual(
            AccountResolver.defaultAccountError(in: values),
            .invalidSetting(
                key: "IRIS_DEFAULT_ACCOUNT",
                reason: "there is no account named \"wrok\". Configured accounts: personal, work."
            )
        )
        XCTAssertEqual(
            try AccountResolver.summaries(in: values).filter(\.isDefault), [],
            "no account is the default"
        )
        XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: values)) { error in
            XCTAssertEqual(error as? IrisError, AccountResolver.defaultAccountError(in: values),
                           "commands without --account throw the same error")
        }
    }

    // MARK: - Google accounts

    private func googleSettings(_ name: String, refreshToken: String? = "1//refresh-\(UUID().uuidString)") -> [String: String] {
        var values = [
            "IRIS_\(name)_IMAP_HOST": "imap.gmail.com",
            "IRIS_\(name)_IMAP_USERNAME": "\(name.lowercased())@gmail.com",
            "IRIS_\(name)_GOOGLE_CLIENT_ID": "id-\(name).apps.googleusercontent.com",
            "IRIS_\(name)_GOOGLE_CLIENT_SECRET": "client-secret-\(name)",
        ]
        values["IRIS_\(name)_GOOGLE_REFRESH_TOKEN"] = refreshToken
        return values
    }

    func testAGoogleAccountResolvesWithItsClientAndRefreshToken() throws {
        let values = googleSettings("PERSONAL", refreshToken: "1//refresh")
        XCTAssertEqual(try AccountResolver.resolve(name: nil, settings: values), Account(
            name: "personal", host: "imap.gmail.com", port: 993, username: "personal@gmail.com",
            authentication: .google(
                GoogleClient(clientID: "id-PERSONAL.apps.googleusercontent.com", clientSecret: "client-secret-PERSONAL"),
                refreshToken: "1//refresh"
            )
        ))
    }

    func testAGoogleAccountWithAPasswordTooIsAnError() {
        var values = googleSettings("PERSONAL")
        values["IRIS_PERSONAL_IMAP_PASSWORD"] = "app-password"
        for resolve in [
            { _ = try AccountResolver.resolve(name: nil, settings: values) },
            { _ = try AccountResolver.resolveGoogleSignIn(name: nil, settings: values) },
        ] {
            XCTAssertThrowsError(try resolve()) { error in
                guard case .invalidSetting(let key, let reason) = error as? IrisError else {
                    return XCTFail("unexpected error \(error)")
                }
                XCTAssertEqual(key, "IRIS_PERSONAL_IMAP_PASSWORD")
                XCTAssertTrue(reason.contains("IRIS_PERSONAL_GOOGLE_CLIENT_ID"), reason)
                XCTAssertTrue(reason.contains("Use one or the other"), reason)
                XCTAssertFalse(reason.contains("app-password"), "the error never shows the password")
            }
        }
    }

    func testAGoogleAccountWithoutARefreshTokenSaysToSignIn() {
        let values = googleSettings("PERSONAL", refreshToken: nil)
        XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: values)) { error in
            XCTAssertEqual(error as? IrisError, .googleNotSignedIn(account: "personal"))
        }
    }

    func testAGoogleAccountWithoutAClientSecretIsMissingASetting() {
        var values = googleSettings("PERSONAL")
        values["IRIS_PERSONAL_GOOGLE_CLIENT_SECRET"] = nil
        XCTAssertThrowsError(try AccountResolver.resolve(name: nil, settings: values)) { error in
            XCTAssertEqual(error as? IrisError, .missingSetting(key: "IRIS_PERSONAL_GOOGLE_CLIENT_SECRET"))
        }
    }

    func testAGoogleAccountNeedsNoPassword() throws {
        let account = try AccountResolver.resolve(name: nil, settings: googleSettings("PERSONAL"))
        guard case .google = account.authentication else {
            return XCTFail("expected a Google account, got \(account.authentication)")
        }
    }

    func testAnAccountWithOnlyGoogleKeysIsFound() {
        let values = [
            "IRIS_ONLY_GOOGLE_GOOGLE_CLIENT_ID": "id",
            "IRIS_SECRET_ONLY_GOOGLE_CLIENT_SECRET": "secret",
            "IRIS_TOKEN_ONLY_GOOGLE_REFRESH_TOKEN": "token",
        ]
        XCTAssertEqual(AccountResolver.accountNames(in: values), ["only_google", "secret_only", "token_only"])
        XCTAssertEqual(AccountResolver.accountName(fromKey: "IRIS_MY_GMAIL_GOOGLE_CLIENT_ID"), "my_gmail")
    }

    func testGoogleKeysWithoutAClientIDLeaveAPasswordAccount() throws {
        var values = settings("WORK")
        values["IRIS_WORK_GOOGLE_CLIENT_SECRET"] = "client-secret"
        values["IRIS_WORK_GOOGLE_REFRESH_TOKEN"] = "1//refresh"
        XCTAssertEqual(try AccountResolver.resolve(name: nil, settings: values).authentication, .password("secret-WORK"))
    }

    func testSummariesReportTheProblemsOfGoogleAccounts() throws {
        var values = googleSettings("READY")
        values.merge(googleSettings("NEW", refreshToken: nil)) { $1 }
        values.merge(googleSettings("BOTH")) { $1 }
        values["IRIS_BOTH_IMAP_PASSWORD"] = "app-password"
        values["IRIS_HALF_GOOGLE_CLIENT_ID"] = "id"

        let summaries = try AccountResolver.summaries(in: values)

        XCTAssertEqual(summaries.map(\.name), ["both", "half", "new", "ready"])
        XCTAssertEqual(summaries.map(\.problems), [
            ["set IRIS_BOTH_IMAP_PASSWORD or IRIS_BOTH_GOOGLE_CLIENT_ID, not both"],
            [
                "missing IRIS_HALF_IMAP_HOST",
                "missing IRIS_HALF_IMAP_USERNAME",
                "missing IRIS_HALF_GOOGLE_CLIENT_SECRET",
                "not signed in: run `iris auth login --account half`",
            ],
            ["not signed in: run `iris auth login --account new`"],
            [],
        ])
        let json = try OutputFormatter.render(summaries, format: .json)
        for secret in ["client-secret", "1//refresh", "app-password"] {
            XCTAssertFalse(json.contains(secret), "\(secret) in \(json)")
        }
    }

    func testResolveGoogleSignInNeedsNoHostAndNoRefreshToken() throws {
        var values = googleSettings("PERSONAL", refreshToken: nil)
        values["IRIS_PERSONAL_IMAP_HOST"] = nil
        XCTAssertEqual(
            try AccountResolver.resolveGoogleSignIn(name: "Personal", settings: values),
            GoogleSignInAccount(
                name: "personal",
                username: "personal@gmail.com",
                client: GoogleClient(
                    clientID: "id-PERSONAL.apps.googleusercontent.com", clientSecret: "client-secret-PERSONAL"
                )
            )
        )
    }

    func testResolveGoogleSignInPicksTheDefaultAccount() throws {
        var values = googleSettings("PERSONAL").merging(settings("WORK")) { $1 }
        XCTAssertThrowsError(try AccountResolver.resolveGoogleSignIn(name: nil, settings: values)) { error in
            XCTAssertEqual(error as? IrisError, .accountNotChosen(available: ["personal", "work"]))
        }
        values[AccountResolver.defaultAccountKey] = "personal"
        XCTAssertEqual(try AccountResolver.resolveGoogleSignIn(name: nil, settings: values).name, "personal")
        XCTAssertThrowsError(try AccountResolver.resolveGoogleSignIn(name: "nope", settings: values)) { error in
            XCTAssertEqual(error as? IrisError, .unknownAccount(name: "nope", available: ["personal", "work"]))
        }
    }

    func testResolveGoogleSignInOfAPasswordAccountNeedsTheClientID() {
        XCTAssertThrowsError(try AccountResolver.resolveGoogleSignIn(name: "work", settings: settings("WORK"))) { error in
            XCTAssertEqual(error as? IrisError, .missingSetting(key: "IRIS_WORK_GOOGLE_CLIENT_ID"))
        }
    }

    func testResolveGoogleSignInNeedsTheUsernameAndTheClientSecret() {
        for missing in ["IRIS_PERSONAL_IMAP_USERNAME", "IRIS_PERSONAL_GOOGLE_CLIENT_SECRET"] {
            var values = googleSettings("PERSONAL")
            values[missing] = nil
            XCTAssertThrowsError(try AccountResolver.resolveGoogleSignIn(name: nil, settings: values)) { error in
                XCTAssertEqual(error as? IrisError, .missingSetting(key: missing))
            }
        }
    }

    func testSecretsListThePasswordOrTheClientSecretAndRefreshToken() throws {
        XCTAssertEqual(try AccountResolver.resolve(name: nil, settings: settings("WORK")).secrets, ["secret-WORK"])
        let google = try AccountResolver.resolve(name: nil, settings: googleSettings("PERSONAL", refreshToken: "1//refresh"))
        XCTAssertEqual(google.secrets, ["client-secret-PERSONAL", "1//refresh"])
    }

    func testDefaultAccountErrorIsNilWhenTheDefaultIsFine() {
        var values = settings("WORK")
        XCTAssertNil(AccountResolver.defaultAccountError(in: values), "the key is not set")
        values[AccountResolver.defaultAccountKey] = "Work"
        XCTAssertNil(AccountResolver.defaultAccountError(in: values), "the key names an account, in any case")
        XCTAssertNil(
            AccountResolver.defaultAccountError(in: [AccountResolver.defaultAccountKey: "work"]),
            "with no accounts, noAccountsConfigured is the problem to report"
        )
    }
}
