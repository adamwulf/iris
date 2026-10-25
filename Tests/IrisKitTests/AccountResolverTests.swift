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

    /// A new empty directory, removed after the test.
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            // A test may make the directory read-only; allow the removal again.
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    func testSaveGoogleRefreshTokenWritesTheFileThatSetsTheClientID() throws {
        let dir = try temporaryDirectory()
        let child = dir.appendingPathComponent("my project", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let parentFile = dir.appendingPathComponent(".env")
        let childFile = child.appendingPathComponent(".env")
        try "IRIS_MY_GMAIL_GOOGLE_CLIENT_ID=id\nIRIS_MY_GMAIL_GOOGLE_REFRESH_TOKEN=old\n".write(
            to: parentFile, atomically: true, encoding: .utf8)
        try "IRIS_WORK_IMAP_HOST=imap.example.com\n".write(to: childFile, atomically: true, encoding: .utf8)

        let save = AccountResolver.saveGoogleRefreshToken("1//new", account: "my_gmail", startingIn: child)

        guard case .saved(let file) = save.outcome else {
            return XCTFail("expected .saved, got \(save.outcome)")
        }
        XCTAssertEqual(file.path, parentFile.path)
        XCTAssertNil(save.stdoutLine, "a saved token is never shown")
        XCTAssertEqual(
            save.message,
            "Signed in. Saved IRIS_MY_GMAIL_GOOGLE_REFRESH_TOKEN in \(parentFile.path).\n"
                + "Run `iris check --account my_gmail` to test the account."
        )
        XCTAssertFalse(save.message.contains("1//new"))
        XCTAssertEqual(
            try String(contentsOf: parentFile, encoding: .utf8),
            "IRIS_MY_GMAIL_GOOGLE_CLIENT_ID=id\nIRIS_MY_GMAIL_GOOGLE_REFRESH_TOKEN=1//new\n"
        )
        XCTAssertEqual(try String(contentsOf: childFile, encoding: .utf8), "IRIS_WORK_IMAP_HOST=imap.example.com\n")
        XCTAssertEqual(
            AccountResolver.settings(environment: [:], startingIn: child)["IRIS_MY_GMAIL_GOOGLE_REFRESH_TOKEN"], "1//new"
        )
    }

    func testSaveGoogleRefreshTokenPrintsTheLineWhenTheClientIDComesFromTheEnvironment() throws {
        let dir = try temporaryDirectory()
        let file = dir.appendingPathComponent(".env")
        try "IRIS_WORK_IMAP_HOST=imap.example.com\n".write(to: file, atomically: true, encoding: .utf8)

        let save = AccountResolver.saveGoogleRefreshToken("1//new", account: "personal", startingIn: dir)

        XCTAssertEqual(save.outcome, .clientIDInEnvironment)
        XCTAssertEqual(save.stdoutLine, "IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN=1//new")
        XCTAssertEqual(
            save.message,
            "Signed in. IRIS_PERSONAL_GOOGLE_CLIENT_ID is not in a .env file (it comes from the environment), "
                + "so iris wrote no file. Save the line IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN=... that iris printed "
                + "where you keep the other keys of the account. "
                + "Run `iris check --account personal` to test the account."
        )
        XCTAssertFalse(save.message.contains("1//new"), "stderr never shows the token")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "IRIS_WORK_IMAP_HOST=imap.example.com\n")
    }

    func testSaveGoogleRefreshTokenPrintsTheLineWhenTheWriteFails() throws {
        let dir = try temporaryDirectory()
        let file = dir.appendingPathComponent(".env")
        try "IRIS_PERSONAL_GOOGLE_CLIENT_ID=id\n".write(to: file, atomically: true, encoding: .utf8)
        // The write replaces the file through a new file in the same directory.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)

        let save = AccountResolver.saveGoogleRefreshToken("1//new", account: "personal", startingIn: dir)

        guard case .writeFailed(let failed, let reason) = save.outcome else {
            return XCTFail("expected .writeFailed, got \(save.outcome)")
        }
        XCTAssertEqual(failed.path, file.path)
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(save.stdoutLine, "IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN=1//new")
        XCTAssertTrue(save.message.hasPrefix(
            "Signed in, but iris could not write IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN to \(file.path): \(reason). "
        ), save.message)
        XCTAssertTrue(save.message.hasSuffix(
            "Save the line IRIS_PERSONAL_GOOGLE_REFRESH_TOKEN=... that iris printed where you keep the other keys "
                + "of the account. Run `iris check --account personal` to test the account."
        ), save.message)
        XCTAssertFalse(save.message.contains("1//new"), "stderr never shows the token")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "IRIS_PERSONAL_GOOGLE_CLIENT_ID=id\n")
    }

    func testRefreshTokenSaveShellQuotesTheAccountInTheCommand() {
        // Account names are letters, digits, and underscores, so quoting never shows today; the
        // message still goes through MessagePage.shellQuoted, as the other messages do.
        let save = RefreshTokenSave(account: "a b", refreshToken: "t", outcome: .clientIDInEnvironment)
        XCTAssertTrue(save.message.contains("`iris check --account 'a b'`"), save.message)
    }

    func testSecretsListThePasswordOrTheClientSecretAndRefreshToken() throws {
        XCTAssertEqual(try AccountResolver.resolve(name: nil, settings: settings("WORK")).secrets, ["secret-WORK"])
        let google = try AccountResolver.resolve(name: nil, settings: googleSettings("PERSONAL", refreshToken: "1//refresh"))
        XCTAssertEqual(google.secrets, ["client-secret-PERSONAL", "1//refresh"])
    }

    // MARK: - From address

    private let work = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com", authentication: .password("secret")
    )

    func testFromKeyUppercasesTheAccountName() {
        XCTAssertEqual(AccountResolver.fromKey(account: "my_gmail"), "IRIS_MY_GMAIL_FROM")
    }

    func testTheFromKeyAloneIsNotAnAccount() {
        XCTAssertNil(AccountResolver.accountName(fromKey: "IRIS_WORK_FROM"))
        var values = settings("WORK").merging(googleSettings("PERSONAL")) { $1 }
        values["IRIS_OTHER_FROM"] = "me@example.com"
        values["IRIS_PERSONAL_FROM"] = "me@gmail.com"
        XCTAssertEqual(AccountResolver.accountNames(in: values), ["personal", "work"])
        XCTAssertEqual(try AccountResolver.summaries(in: values).map(\.problems), [[], []], "accounts does not check it")
    }

    func testFromAddressReadsANameAndAnAddress() throws {
        let values = ["IRIS_WORK_FROM": "Jane Doe <jane@example.com>"]
        XCTAssertEqual(
            try AccountResolver.fromAddress(for: work, in: values),
            MailAddress(name: "Jane Doe", address: "jane@example.com")
        )
    }

    func testFromAddressReadsAQuotedName() throws {
        let values = ["IRIS_WORK_FROM": #""Doe, Jane" <jane@example.com>"#]
        XCTAssertEqual(try AccountResolver.fromAddress(for: work, in: values).name, "Doe, Jane")
    }

    func testFromAddressReadsABareAddress() throws {
        let values = ["IRIS_WORK_FROM": "jane@example.com"]
        XCTAssertEqual(
            try AccountResolver.fromAddress(for: work, in: values),
            MailAddress(name: nil, address: "jane@example.com")
        )
    }

    func testFromAddressWinsOverTheUsername() throws {
        let values = ["IRIS_WORK_FROM": "other@example.com"]
        XCTAssertEqual(try AccountResolver.fromAddress(for: work, in: values).address, "other@example.com")
    }

    func testFromAddressFallsBackToAUsernameThatIsAnAddress() throws {
        XCTAssertEqual(
            try AccountResolver.fromAddress(for: work, in: [:]),
            MailAddress(name: nil, address: "me@example.com")
        )
    }

    /// A Google account's username is the address chosen at Google sign-in.
    func testFromAddressOfAGoogleAccountFallsBackToItsSignInAddress() throws {
        let values = googleSettings("PERSONAL")
        let account = try AccountResolver.resolve(name: nil, settings: values)
        XCTAssertEqual(
            try AccountResolver.fromAddress(for: account, in: values),
            MailAddress(name: nil, address: "personal@gmail.com")
        )
        var named = values
        named["IRIS_PERSONAL_FROM"] = "Me <me@example.com>"
        XCTAssertEqual(try AccountResolver.fromAddress(for: account, in: named).address, "me@example.com")
    }

    func testFromAddressWithoutTheKeyOrAnAddressUsernameNamesTheKey() {
        let icloud = Account(
            name: "icloud", host: "imap.mail.me.com", port: 993, username: "emily", authentication: .password("secret")
        )
        XCTAssertThrowsError(try AccountResolver.fromAddress(for: icloud, in: [:])) { error in
            XCTAssertEqual(error as? IrisError, .draftFromAddressMissing(account: "icloud", username: "emily"))
        }
    }

    func testFromAddressWithoutAnAddressInTheKeyNamesTheKey() {
        for bad in ["Jane Doe", "jane", "jane@", "@example.com", "Jane <>", "a@example.com, b@example.com"] {
            XCTAssertThrowsError(try AccountResolver.fromAddress(for: work, in: ["IRIS_WORK_FROM": bad])) { error in
                guard case .invalidSetting(let key, let reason) = error as? IrisError else {
                    return XCTFail("unexpected error \(error) for \(bad)")
                }
                XCTAssertEqual(key, "IRIS_WORK_FROM")
                XCTAssertTrue(reason.contains("\"\(bad)\" is not an email address"), reason)
            }
        }
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
