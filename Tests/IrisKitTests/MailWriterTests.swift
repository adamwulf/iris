import Foundation
import XCTest
@testable import IrisKit

final class MailWriterTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )

    private func writer(_ fake: FakeMailClient) -> MailWriter {
        MailWriter(account: account, makeClient: { _ in fake })
    }

    /// The iris ID of `uid` in `mailbox` of the test account.
    private func id(_ uid: UInt32, in mailbox: String = "INBOX") -> IrisID {
        IrisID(account: account.name, mailbox: mailbox, uid: uid)
    }

    private func assertThrows(
        _ expected: IrisError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected), but nothing was thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? IrisError, expected, file: file, line: line)
        }
    }

    // MARK: - read and unread

    func testMarkReadSelectsTheMailboxFindsTheMessageAndAddsSeen() async throws {
        let fake = FakeMailClient.inbox(count: 3)

        try await writer(fake).markRead(id(102))

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([102]), .setSeen(true, 102), .logout])
    }

    func testMarkUnreadSelectsTheMailboxFindsTheMessageAndRemovesSeen() async throws {
        let fake = FakeMailClient.inbox(count: 3)

        try await writer(fake).markUnread(id(102))

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([102]), .setSeen(false, 102), .logout])
    }

    func testTheStoreDoesNotDependOnTheCurrentFlag() async throws {
        // Not a toggle: read always adds \Seen and unread always removes it, so
        // running either one twice gives the same result.
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 2, uidValidity: 7, uidNext: 200)],
            envelopes: [
                FakeMailClient.envelope(sequenceNumber: 1, seen: true),
                FakeMailClient.envelope(sequenceNumber: 2, seen: false),
            ]
        )

        try await writer(fake).markRead(id(101))
        try await writer(fake).markUnread(id(102))

        let stores = await fake.calls.filter {
            if case .setSeen = $0 { return true }
            return false
        }
        XCTAssertEqual(stores, [.setSeen(true, 101), .setSeen(false, 102)])
    }

    func testSelectsTheModifiedUTF7Name() async throws {
        let fake = FakeMailClient(
            statuses: ["[Gmail]/Entw&APw-rfe": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [FakeMailClient.envelope(sequenceNumber: 1)]
        )

        try await writer(fake).markRead(id(101, in: "[Gmail]/Entwürfe"))

        let calls = await fake.calls
        XCTAssertEqual(calls, [
            .login, .select("[Gmail]/Entw&APw-rfe"), .fetchEnvelopesByUID([101]), .setSeen(true, 101), .logout,
        ])
    }

    // MARK: - errors

    func testMissingMessageThrowsUnknownMessageAndChangesNothing() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMessage(id(999))) { try await self.writer(fake).markRead(self.id(999)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([999]), .logout])
    }

    func testUIDZeroIsRejectedBeforeConnecting() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMessage(id(0))) { try await self.writer(fake).markUnread(self.id(0)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testUnknownMailboxErrorHasTheNameTheUserTypedNotTheWireName() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMailbox(account: "work", name: "R&D", reason: "NO no such mailbox")) {
            try await self.writer(fake).markRead(self.id(101, in: "R&D"))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("R&-D"), .logout])
    }

    func testFailedStoreStillLogsOut() async {
        let failure = IrisError.serverError(account: "work", command: "STORE", reason: "Store failed: NO read-only")
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [FakeMailClient.envelope(sequenceNumber: 1)],
            errors: [.setSeen: failure]
        )

        await assertThrows(failure) { try await self.writer(fake).markRead(self.id(101)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .select("INBOX"), .fetchEnvelopesByUID([101]), .setSeen(true, 101), .logout])
    }

    func testFailedLoginStillLogsOutAndDoesNothingElse() async {
        let failure = IrisError.loginFailed(
            account: "work", username: "me@example.com", host: "imap.example.com", reason: "NO invalid credentials"
        )
        let fake = FakeMailClient(errors: [.login: failure])

        await assertThrows(failure) { try await self.writer(fake).markRead(self.id(101)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .logout])
    }
}
