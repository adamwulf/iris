import Foundation
import XCTest
@testable import IrisKit

final class MailModelsTests: XCTestCase {
    /// 2026-10-24 20:21:18 UTC.
    private let sampleDate = Date(timeIntervalSince1970: 1_792_873_278)

    private func page(
        mailbox: String = "INBOX",
        count: Int,
        totalCount: Int,
        page: Int = 1,
        limit: Int = 25,
        hasMore: Bool
    ) -> MessagePage {
        let messages = (0..<count).map { MessageSummary(uid: UInt32(500 - $0), from: nil, subject: "", date: nil) }
        return MessagePage(
            mailbox: mailbox, messages: messages, totalCount: totalCount, page: page, limit: limit, hasMore: hasMore
        )
    }

    // MARK: - Paging math

    func testSequenceRangeCountsPagesFromTheNewestMessage() {
        XCTAssertEqual(MessagePage.sequenceRange(messageCount: 60, page: 1, limit: 25), 36...60)
        XCTAssertEqual(MessagePage.sequenceRange(messageCount: 60, page: 2, limit: 25), 11...35)
        XCTAssertEqual(MessagePage.sequenceRange(messageCount: 60, page: 3, limit: 25), 1...10)
        XCTAssertEqual(MessagePage.sequenceRange(messageCount: 50, page: 2, limit: 25), 1...25)
        XCTAssertEqual(MessagePage.sequenceRange(messageCount: 3, page: 1, limit: 25), 1...3)
        XCTAssertEqual(MessagePage.sequenceRange(messageCount: 1, page: 1, limit: 1), 1...1)
    }

    func testSequenceRangeIsNilPastTheEndAndForAnEmptyMailbox() {
        XCTAssertNil(MessagePage.sequenceRange(messageCount: 60, page: 4, limit: 25))
        XCTAssertNil(MessagePage.sequenceRange(messageCount: 50, page: 3, limit: 25))
        XCTAssertNil(MessagePage.sequenceRange(messageCount: 0, page: 1, limit: 25))
    }

    func testSequenceRangeDoesNotOverflow() {
        XCTAssertNil(MessagePage.sequenceRange(messageCount: 60, page: Int.max, limit: Int.max))
        XCTAssertNil(MessagePage.sequenceRange(messageCount: 60, page: 2, limit: Int.max))
        XCTAssertEqual(MessagePage.sequenceRange(messageCount: 60, page: 1, limit: Int.max), 1...60)
    }

    // MARK: - Hint line

    func testHintShowsTheRangeAndTheNextPageCommand() {
        XCTAssertEqual(
            page(count: 25, totalCount: 1234, hasMore: true).hint(account: nil),
            "Showing 1-25 of 1234. Next page: iris list --page 2"
        )
    }

    func testHintNextPageCommandKeepsTheAccountMailboxAndLimit() {
        let middle = page(mailbox: "Sent Items", count: 10, totalCount: 60, page: 2, limit: 10, hasMore: true)
        XCTAssertEqual(
            middle.hint(account: "work"),
            "Showing 11-20 of 60. Next page: iris list --account work --mailbox 'Sent Items' --page 3 --limit 10"
        )
    }

    func testHintOnTheLastPageHasNoNextPage() {
        XCTAssertEqual(page(count: 10, totalCount: 60, page: 3, hasMore: false).hint(account: nil), "Showing 51-60 of 60.")
    }

    func testHintForAnEmptyMailboxAndForAPagePastTheEnd() {
        XCTAssertEqual(page(count: 0, totalCount: 0, hasMore: false).hint(account: nil), "\"INBOX\" has no messages.")
        XCTAssertEqual(
            page(count: 0, totalCount: 60, page: 9, hasMore: false).hint(account: nil),
            "Page 9 is past the end: \"INBOX\" has 60 messages, and the last page is 3."
        )
        XCTAssertEqual(
            page(count: 0, totalCount: 1, page: 2, hasMore: false).hint(account: nil),
            "Page 2 is past the end: \"INBOX\" has 1 message, and the last page is 1."
        )
    }

    func testListCommandLeavesOutDefaults() {
        XCTAssertEqual(MessagePage.listCommand(account: nil, mailbox: "INBOX", page: 1, limit: 25), "iris list")
        XCTAssertEqual(
            MessagePage.listCommand(account: "my_gmail", mailbox: "[Gmail]/All Mail", page: 1, limit: 25),
            "iris list --account my_gmail --mailbox '[Gmail]/All Mail'"
        )
    }

    func testShellQuotingQuotesOnlyWhenNeeded() {
        XCTAssertEqual(MessagePage.shellQuoted("INBOX"), "INBOX")
        XCTAssertEqual(MessagePage.shellQuoted("Work/2026.Q4"), "Work/2026.Q4")
        XCTAssertEqual(MessagePage.shellQuoted("Sent Items"), "'Sent Items'")
        XCTAssertEqual(MessagePage.shellQuoted("Bob's"), #"'Bob'\''s'"#)
        XCTAssertEqual(MessagePage.shellQuoted("$HOME"), "'$HOME'")
        XCTAssertEqual(MessagePage.shellQuoted(""), "''")
    }

    // MARK: - MessageSummary

    func testTableDateIsMinutePrecisionInTheGivenTimeZone() throws {
        let chicago = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(DateText.string(from: sampleDate, timeZone: chicago), "2026-10-24 15:21")
        XCTAssertEqual(DateText.string(from: sampleDate, timeZone: utc), "2026-10-24 20:21")
    }

    func testTableRowUsesLocalTimeAndTheSenderName() throws {
        let local = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026, month: 3, day: 7, hour: 9, minute: 5
        )))
        let summary = MessageSummary(
            uid: 42, from: MailAddress(name: "Jane Doe", address: "jane@example.com"), subject: "Hello", date: local
        )
        XCTAssertEqual(summary.tableValues, ["42", "2026-03-07 09:05", "Jane Doe", "Hello"])
        XCTAssertEqual(summary.idValue, "42")
    }

    func testTableFromFallsBackToTheAddressAndEmptyValuesStayEmpty() {
        let noName = MessageSummary(uid: 1, from: MailAddress(name: nil, address: "bot@example.com"), subject: "", date: nil)
        let emptyName = MessageSummary(uid: 2, from: MailAddress(name: "", address: "x@example.com"), subject: "", date: nil)
        let noSender = MessageSummary(uid: 3, from: nil, subject: "", date: nil)
        XCTAssertEqual(noName.tableValues, ["1", "", "bot@example.com", ""])
        XCTAssertEqual(emptyName.tableValues, ["2", "", "x@example.com", ""])
        XCTAssertEqual(noSender.tableValues, ["3", "", "", ""])
    }

    func testTableCellsAreOneLine() {
        let summary = MessageSummary(
            uid: 1, from: MailAddress(name: "Jane\tDoe", address: "j@example.com"), subject: "Long\r\n subject", date: nil
        )
        XCTAssertEqual(summary.tableValues, ["1", "", "Jane Doe", "Long  subject"])
    }

    func testJSONHasTheFullSenderAndAnISO8601Date() throws {
        let summary = MessageSummary(
            uid: 101, from: MailAddress(name: "Jane Doe", address: "jane@example.com"), subject: "Hi", date: sampleDate
        )
        XCTAssertEqual(
            try OutputFormatter.render([summary], format: .jsonl),
            #"{"date":"2026-10-24T20:21:18Z","from":{"address":"jane@example.com","name":"Jane Doe"},"subject":"Hi","uid":101}"#
        )
    }

    func testTableColumns() throws {
        let summary = MessageSummary(uid: 7, from: nil, subject: "Hi", date: nil)
        XCTAssertEqual(try OutputFormatter.render([summary], format: .table), """
        UID  DATE  FROM  SUBJECT
        7                Hi
        """)
    }

    // MARK: - MailboxInfo

    func testMergedKeepsFirstOrderAndUnitesAttributes() {
        let merged = MailboxInfo.merged([
            MailboxInfo(name: "Sent", attributes: []),
            MailboxInfo(name: "INBOX", attributes: []),
            MailboxInfo(name: "Sent", attributes: [#"\Sent"#]),
            MailboxInfo(name: "All", attributes: [#"\Archive"#, #"\All"#]),
            MailboxInfo(name: "All", attributes: [#"\All"#]),
        ])
        XCTAssertEqual(merged, [
            MailboxInfo(name: "Sent", attributes: [#"\Sent"#]),
            MailboxInfo(name: "INBOX", attributes: []),
            MailboxInfo(name: "All", attributes: [#"\All"#, #"\Archive"#]),
        ])
    }

    func testNameOrderIgnoresCase() {
        let names = ["work", "INBOX", "Archive", "archive", "[Gmail]/Drafts"]
            .map { MailboxInfo(name: $0, attributes: []) }
            .sorted(by: MailboxInfo.areInNameOrder)
            .map(\.name)
        XCTAssertEqual(names, ["[Gmail]/Drafts", "Archive", "archive", "INBOX", "work"])
    }

    func testMailboxTableAndJSON() throws {
        let mailboxes = [
            MailboxInfo(name: "INBOX", attributes: []),
            MailboxInfo(name: "Sent", attributes: [#"\Sent"#]),
            MailboxInfo(name: "[Gmail]/All Mail", attributes: [#"\All"#, #"\Archive"#]),
        ]
        XCTAssertEqual(try OutputFormatter.render(mailboxes, format: .table), #"""
        NAME              ATTRIBUTES
        INBOX
        Sent              \Sent
        [Gmail]/All Mail  \All \Archive
        """#)
        XCTAssertEqual(
            try OutputFormatter.render([mailboxes[1]], format: .jsonl),
            #"{"attributes":["\\Sent"],"name":"Sent"}"#
        )
        XCTAssertEqual(try OutputFormatter.render(mailboxes, format: .id), "INBOX\nSent\n[Gmail]/All Mail")
    }

    // MARK: - AccountCheck

    func testCheckReportHasOneFactPerLineAndNoPassword() {
        let account = Account(name: "work", host: "imap.zoho.com", port: 993, username: "me@example.com", password: "hunter2")
        let check = AccountCheck(account: account, capabilities: ["IMAP4rev1", "IDLE", "AUTH=PLAIN"], inboxMessageCount: 1)
        XCTAssertEqual(check.report, """
        Account:      work
        Username:     me@example.com
        Server:       imap.zoho.com:993
        Capabilities: IMAP4rev1 IDLE AUTH=PLAIN
        INBOX:        1 message
        """)
        XCTAssertFalse(check.report.contains("hunter2"))
    }
}
