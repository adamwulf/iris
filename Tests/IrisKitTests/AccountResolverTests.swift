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
            username: "work@example.com", password: "secret-WORK"
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
