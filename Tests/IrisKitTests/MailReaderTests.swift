import Foundation
import XCTest
@testable import IrisKit

final class MailReaderTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com", password: "secret"
    )

    private func reader(_ fake: FakeMailClient) -> MailReader {
        MailReader(account: account, makeClient: { _ in fake })
    }

    /// The iris ID of `uid` in `mailbox` of the test account.
    private func id(_ uid: UInt32, in mailbox: String = "INBOX") -> IrisID {
        IrisID(account: account.name, mailbox: mailbox, uid: uid)
    }

    /// The UIDs in `range`, newest (largest) first.
    private func uidsNewestFirst(_ range: ClosedRange<Int>) -> [UInt32] {
        range.reversed().map { UInt32($0) }
    }

    private func assertThrows<T>(
        _ expected: IrisError,
        _ body: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected), but nothing was thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? IrisError, expected, file: file, line: line)
        }
    }

    // MARK: - check

    func testCheckReportsCapabilitiesAndTheInboxCountAndLogsOut() async throws {
        let fake = FakeMailClient(
            capabilities: ["IMAP4rev1", "IDLE", "AUTH=PLAIN"],
            statuses: ["INBOX": MailboxStatus(messageCount: 1234, uidValidity: 7, uidNext: 5000)]
        )

        let check = try await reader(fake).check()

        XCTAssertEqual(check.account, "work")
        XCTAssertEqual(check.username, "me@example.com")
        XCTAssertEqual(check.host, "imap.example.com")
        XCTAssertEqual(check.port, 993)
        XCTAssertEqual(check.capabilities, ["IMAP4rev1", "IDLE", "AUTH=PLAIN"])
        XCTAssertEqual(check.inboxMessageCount, 1234)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .capabilities, .examine("INBOX"), .logout])
    }

    // MARK: - mailboxes

    func testMailboxesMergesAttributesByNameAndSortsByName() async throws {
        let fake = FakeMailClient(mailboxes: [
            MailboxInfo(name: "INBOX", attributes: []),
            MailboxInfo(name: "[Gmail]/Sent Mail", attributes: []),
            MailboxInfo(name: "archive", attributes: []),
            MailboxInfo(name: "[Gmail]/Sent Mail", attributes: [#"\Sent"#]),
            MailboxInfo(name: "[Gmail]/All Mail", attributes: [#"\All"#]),
            MailboxInfo(name: "[Gmail]/All Mail", attributes: [#"\Archive"#, #"\All"#]),
        ])

        let mailboxes = try await reader(fake).mailboxes()

        XCTAssertEqual(mailboxes, [
            MailboxInfo(name: "[Gmail]/All Mail", attributes: [#"\All"#, #"\Archive"#]),
            MailboxInfo(name: "[Gmail]/Sent Mail", attributes: [#"\Sent"#]),
            MailboxInfo(name: "archive", attributes: []),
            MailboxInfo(name: "INBOX", attributes: []),
        ])
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .listMailboxes, .logout])
    }

    func testMailboxesDecodesTheWireNamesBeforeMerging() async throws {
        let fake = FakeMailClient(mailboxes: [
            MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: []),
            MailboxInfo(name: "R&-D", attributes: []),
            MailboxInfo(name: "[Gmail]/Entw&APw-rfe", attributes: [#"\Drafts"#]),
            MailboxInfo(name: "Bad&Name", attributes: []),
        ])

        let mailboxes = try await reader(fake).mailboxes()

        XCTAssertEqual(mailboxes, [
            MailboxInfo(name: "[Gmail]/Entwürfe", attributes: [#"\Drafts"#]),
            MailboxInfo(name: "Bad&Name", attributes: []),
            MailboxInfo(name: "R&D", attributes: []),
        ], "a name that is not valid modified UTF-7 stays as the server sent it")
    }

    // MARK: - list paging

    func testFirstPageHasTheNewestMessagesNewestFirst() async throws {
        let fake = FakeMailClient.inbox(count: 60)

        let page = try await reader(fake).list()

        XCTAssertEqual(page.messages.map(\.irisID.uid), uidsNewestFirst(136...160))
        XCTAssertEqual(page.totalCount, 60)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.limit, 25)
        XCTAssertEqual(page.mailbox, "INBOX")
        XCTAssertTrue(page.hasMore)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchEnvelopes(36...60), .logout])
    }

    func testMiddlePage() async throws {
        let fake = FakeMailClient.inbox(count: 60)

        let page = try await reader(fake).list(page: 2)

        XCTAssertEqual(page.messages.map(\.irisID.uid), uidsNewestFirst(111...135))
        XCTAssertTrue(page.hasMore)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchEnvelopes(11...35), .logout])
    }

    func testLastPageIsPartial() async throws {
        let fake = FakeMailClient.inbox(count: 60)

        let page = try await reader(fake).list(page: 3)

        XCTAssertEqual(page.messages.map(\.irisID.uid), uidsNewestFirst(101...110))
        XCTAssertFalse(page.hasMore)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchEnvelopes(1...10), .logout])
    }

    func testLastPageThatIsExactlyFullHasNoMore() async throws {
        let fake = FakeMailClient.inbox(count: 50)

        let page = try await reader(fake).list(page: 2)

        XCTAssertEqual(page.messages.count, 25)
        XCTAssertFalse(page.hasMore)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchEnvelopes(1...25), .logout])
    }

    func testPagePastTheEndIsEmptyAndFetchesNothing() async throws {
        let fake = FakeMailClient.inbox(count: 60)

        let page = try await reader(fake).list(page: 4)

        XCTAssertEqual(page.messages, [])
        XCTAssertEqual(page.totalCount, 60)
        XCTAssertEqual(page.page, 4)
        XCTAssertFalse(page.hasMore)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .logout])
    }

    func testHugePageNumberIsPastTheEndAndDoesNotOverflow() async throws {
        let fake = FakeMailClient.inbox(count: 60)

        let page = try await reader(fake).list(page: Int.max, limit: Int.max)

        XCTAssertEqual(page.messages, [])
        XCTAssertFalse(page.hasMore)
    }

    func testEmptyMailboxGivesAnEmptyPage() async throws {
        let fake = FakeMailClient.inbox(count: 0)

        let page = try await reader(fake).list()

        XCTAssertEqual(page.messages, [])
        XCTAssertEqual(page.totalCount, 0)
        XCTAssertFalse(page.hasMore)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .logout])
    }

    func testLimitLargerThanTheMailboxShowsEverything() async throws {
        let fake = FakeMailClient.inbox(count: 3)

        let page = try await reader(fake).list(limit: 25)

        XCTAssertEqual(page.messages.map(\.irisID.uid), [103, 102, 101])
        XCTAssertFalse(page.hasMore)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchEnvelopes(1...3), .logout])
    }

    func testListOrdersBySequenceNumberWhateverOrderTheServerAnswersIn() async throws {
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 4, uidValidity: 7, uidNext: 200)],
            envelopes: [3, 1, 4, 2].map { FakeMailClient.envelope(sequenceNumber: $0) }
        )

        let page = try await reader(fake).list()

        XCTAssertEqual(page.messages.map(\.irisID.uid), [104, 103, 102, 101])
    }

    func testListUsesTheGivenMailbox() async throws {
        let fake = FakeMailClient(
            statuses: ["Sent": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [FakeMailClient.envelope(sequenceNumber: 1)]
        )

        let page = try await reader(fake).list(mailbox: "Sent")

        XCTAssertEqual(page.mailbox, "Sent")
        XCTAssertEqual(page.messages.map(\.irisID.description), ["work/Sent/101"])
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("Sent"), .fetchEnvelopes(1...1), .logout])
    }

    func testListExaminesTheModifiedUTF7NameAndKeepsTheDecodedName() async throws {
        let fake = FakeMailClient(
            statuses: ["[Gmail]/Entw&APw-rfe": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [FakeMailClient.envelope(sequenceNumber: 1)]
        )

        let page = try await reader(fake).list(mailbox: "[Gmail]/Entwürfe")

        XCTAssertEqual(page.mailbox, "[Gmail]/Entwürfe")
        XCTAssertEqual(page.messages.map(\.irisID), [IrisID(account: "work", mailbox: "[Gmail]/Entwürfe", uid: 101)])
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("[Gmail]/Entw&APw-rfe"), .fetchEnvelopes(1...1), .logout])
    }

    func testListGivesINBOXInOneFormWhateverCaseTheUserTyped() async throws {
        // A server opens INBOX in any case (RFC 3501, section 5.1).
        let fake = FakeMailClient(
            statuses: ["inbox": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [FakeMailClient.envelope(sequenceNumber: 1)]
        )

        let page = try await reader(fake).list(mailbox: "inbox")

        XCTAssertEqual(page.messages.map(\.irisID.description), ["work/INBOX/101"])
    }

    func testUnknownMailboxErrorHasTheNameTheUserTypedNotTheWireName() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMailbox(account: "work", name: "R&D", reason: "NO no such mailbox")) {
            try await self.reader(fake).list(mailbox: "R&D")
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("R&-D"), .logout])
    }

    func testOtherExamineErrorsPassThrough() async {
        let failure = IrisError.serverTimedOut(account: "work", command: "EXAMINE")
        let fake = FakeMailClient(errors: [.examine: failure])

        await assertThrows(failure) { try await self.reader(fake).list(mailbox: "R&D") }
    }

    func testListUsesTheDateHeaderElseTheInternalDate() async throws {
        let header = Date(timeIntervalSince1970: 1_000_000)
        let received = Date(timeIntervalSince1970: 2_000_000)
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 3, uidValidity: 7, uidNext: 200)],
            envelopes: [
                FakeMailClient.envelope(sequenceNumber: 1, date: header, internalDate: received),
                FakeMailClient.envelope(sequenceNumber: 2, date: nil, internalDate: received),
                FakeMailClient.envelope(sequenceNumber: 3, date: nil, internalDate: nil),
            ]
        )

        let page = try await reader(fake).list()

        XCTAssertEqual(page.messages.map(\.date), [nil, received, header])
    }

    func testListKeepsSenderAndSubjectAndUsesAnEmptySubjectWhenThereIsNone() async throws {
        let sender = MailAddress(name: nil, address: "bot@example.com")
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            envelopes: [
                MessageEnvelope(
                    sequenceNumber: 1, uid: 101, seen: true, from: sender, subject: nil, date: nil, internalDate: nil
                ),
            ]
        )

        let page = try await reader(fake).list()

        XCTAssertEqual(page.messages, [
            MessageSummary(
                irisID: IrisID(account: "work", mailbox: "INBOX", uid: 101), from: sender, subject: "", date: nil, unread: false
            ),
        ])
    }

    func testListMarksTheMessagesWithoutTheSeenFlagAsUnread() async throws {
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 3, uidValidity: 7, uidNext: 200)],
            envelopes: [
                FakeMailClient.envelope(sequenceNumber: 1, seen: true),
                FakeMailClient.envelope(sequenceNumber: 2, seen: false),
                FakeMailClient.envelope(sequenceNumber: 3, seen: true),
            ]
        )

        let page = try await reader(fake).list()

        XCTAssertEqual(page.messages.map(\.unread), [false, true, false])
    }

    // MARK: - list errors

    func testPageBelowOneIsRejectedBeforeConnecting() async {
        let fake = FakeMailClient.inbox(count: 10)

        await assertThrows(.invalidPage(0)) { try await self.reader(fake).list(page: 0) }
        await assertThrows(.invalidPage(-3)) { try await self.reader(fake).list(page: -3) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testLimitBelowOneIsRejectedBeforeConnecting() async {
        let fake = FakeMailClient.inbox(count: 10)

        await assertThrows(.invalidLimit(0)) { try await self.reader(fake).list(limit: 0) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testUnknownMailboxThrowsAndLogsOut() async {
        let fake = FakeMailClient.inbox(count: 10)

        await assertThrows(.unknownMailbox(account: "work", name: "Nope", reason: "NO no such mailbox")) {
            try await self.reader(fake).list(mailbox: "Nope")
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("Nope"), .logout])
    }

    func testFailedFetchStillLogsOut() async {
        let failure = IrisError.serverError(account: "work", command: "FETCH", reason: "NO server busy")
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 5, uidValidity: 7, uidNext: 200)],
            errors: [.fetchEnvelopes: failure]
        )

        await assertThrows(failure) { try await self.reader(fake).list() }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchEnvelopes(1...5), .logout])
    }

    func testFailedLoginStillLogsOutAndDoesNothingElse() async {
        let failure = IrisError.loginFailed(
            account: "work", username: "me@example.com", host: "imap.example.com", reason: "NO invalid credentials"
        )
        let fake = FakeMailClient(errors: [.login: failure])

        await assertThrows(failure) { try await self.reader(fake).check() }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .logout])
    }

    func testEachCallUsesANewClientForTheAccount() async throws {
        let fake = FakeMailClient.inbox(count: 1)
        let accounts = Accounts()
        let reader = MailReader(account: account) { account in
            accounts.append(account)
            return fake
        }

        _ = try await reader.list()
        _ = try await reader.check()

        XCTAssertEqual(accounts.all, [account, account])
    }

    // MARK: - rawMessage

    func testRawMessageExaminesTheMailboxAndReturnsTheBytes() async throws {
        let bytes = Data("Subject: Hi\r\n\r\nHello\r\n".utf8)
        let fake = FakeMailClient(
            statuses: ["Archive": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            rawMessages: [150: bytes]
        )

        let data = try await reader(fake).rawMessage(id(150, in: "Archive"))

        XCTAssertEqual(data, bytes)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("Archive"), .fetchRawMessage(150), .logout])
    }

    func testRawMessageExaminesTheModifiedUTF7Name() async throws {
        let bytes = Data("Subject: Hi\r\n\r\nHello\r\n".utf8)
        let fake = FakeMailClient(
            statuses: ["~peter/mail/&U,BTFw-/&ZeVnLIqe-": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            rawMessages: [150: bytes]
        )

        let data = try await reader(fake).rawMessage(id(150, in: "~peter/mail/台北/日本語"))

        XCTAssertEqual(data, bytes)
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("~peter/mail/&U,BTFw-/&ZeVnLIqe-"), .fetchRawMessage(150), .logout])
    }

    func testRawMessageForAMissingUIDThrowsUnknownMessageAndLogsOut() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMessage(id(999))) {
            try await self.reader(fake).rawMessage(self.id(999))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchRawMessage(999), .logout])
    }

    func testUnknownMessageErrorHasTheDecodedMailboxName() async {
        let fake = FakeMailClient(
            statuses: ["[Gmail]/Entw&APw-rfe": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)]
        )

        await assertThrows(.unknownMessage(id(999, in: "[Gmail]/Entwürfe"))) {
            try await self.reader(fake).rawMessage(self.id(999, in: "[Gmail]/Entwürfe"))
        }
    }

    func testRawMessageForUIDZeroIsRejectedBeforeConnecting() async {
        let fake = FakeMailClient.inbox(count: 1)

        await assertThrows(.unknownMessage(id(0))) {
            try await self.reader(fake).rawMessage(self.id(0))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testRawMessageTimeoutPassesThroughAndLogsOut() async {
        let failure = IrisError.messageDownloadTimedOut(seconds: 10)
        let fake = FakeMailClient(
            statuses: ["INBOX": MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            errors: [.fetchRawMessage: failure]
        )

        await assertThrows(failure) { try await self.reader(fake).rawMessage(self.id(101)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchRawMessage(101), .logout])
    }
}

/// Collects the accounts a client factory was called with.
private final class Accounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Account] = []

    func append(_ account: Account) {
        lock.withLock { values.append(account) }
    }

    var all: [Account] {
        lock.withLock { values }
    }
}
