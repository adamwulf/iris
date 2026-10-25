import XCTest
@testable import IrisKit

final class FileLogPolicyTests: XCTestCase {
    func testReadOnlyInvocationsNeverWriteFiles() {
        for arguments in [["ro"], ["ro", "show", "work/INBOX/1"], ["--", "ro", "accounts"]] {
            XCTAssertFalse(FileLogPolicy.writesFiles(arguments: arguments))
        }
        XCTAssertTrue(FileLogPolicy.writesFiles(arguments: ["list", "--subject", "ro"]))
    }

    func testRedactsEveryAccountsSecretsEvenWithoutCompleteConfiguration() {
        let policy = FileLogPolicy(settings: [
            "IRIS_WORK_IMAP_PASSWORD": "password",
            "IRIS_MY_GMAIL_GOOGLE_CLIENT_SECRET": "password-longer",
            "IRIS_MY_GMAIL_GOOGLE_REFRESH_TOKEN": "refresh-token",
            "IRIS_EMPTY_IMAP_PASSWORD": "",
        ])
        XCTAssertEqual(
            policy.redacting("password-longer password refresh-token password"),
            "<redacted> <redacted> <redacted> <redacted>"
        )
        XCTAssertEqual(policy.redacting("Downloading work/INBOX/1"), "Downloading work/INBOX/1")
    }

    func testFailureKeepsActionableIrisErrorsButDoesNotCopyArbitraryErrors() {
        let policy = FileLogPolicy(settings: ["IRIS_WORK_IMAP_PASSWORD": "secret"])
        let error = IrisError.invalidSetting(key: "IRIS_WORK_IMAP_PORT", reason: "secret is not a port")
        XCTAssertTrue(policy.failure(error, command: "check").contains("<redacted> is not a port"))
        XCTAssertEqual(
            policy.failure(NSError(domain: "private draft body", code: 1), command: "reply"),
            "reply: Command did not complete."
        )
    }
}
