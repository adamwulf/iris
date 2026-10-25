import Foundation
import XCTest
@testable import IrisKit

final class MailModelsTests: XCTestCase {
    /// 2026-10-24 20:21:18 UTC.
    private let sampleDate = Date(timeIntervalSince1970: 1_792_873_278)

    private func id(_ uid: UInt32, mailbox: String = "INBOX") -> IrisID {
        IrisID(account: "work", mailbox: mailbox, uid: uid)
    }

    private func page(
        mailbox: String = "INBOX",
        filter: MessageFilter = MessageFilter(),
        count: Int,
        totalCount: Int,
        page: Int = 1,
        limit: Int = 25,
        hasMore: Bool
    ) -> MessagePage {
        let messages = (0..<count).map {
            MessageSummary(irisID: id(UInt32(500 - $0), mailbox: mailbox), from: nil, subject: "", date: nil, unread: false)
        }
        return MessagePage(
            mailbox: mailbox,
            filter: filter,
            messages: messages,
            totalCount: totalCount,
            page: page,
            limit: limit,
            hasMore: hasMore
        )
    }

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(parsing: text)
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
            page(count: 25, totalCount: 1234, hasMore: true).hint(account: nil, format: .table),
            "Showing 1-25 of 1234. Next page: iris list --page 2"
        )
    }

    func testHintNextPageCommandKeepsTheAccountMailboxAndLimit() {
        let middle = page(mailbox: "Sent Items", count: 10, totalCount: 60, page: 2, limit: 10, hasMore: true)
        XCTAssertEqual(
            middle.hint(account: "work", format: .table),
            "Showing 11-20 of 60. Next page: iris list --account work --mailbox 'Sent Items' --page 3 --limit 10"
        )
    }

    func testHintNextPageCommandKeepsTheFormat() {
        let first = page(count: 25, totalCount: 1234, hasMore: true)
        for format in [OutputFormat.json, .jsonl, .id] {
            XCTAssertEqual(
                first.hint(account: nil, format: format),
                "Showing 1-25 of 1234. Next page: iris list --page 2 --format \(format.rawValue)"
            )
        }
    }

    func testHintOnTheLastPageHasNoNextPage() {
        XCTAssertEqual(page(count: 10, totalCount: 60, page: 3, hasMore: false).hint(account: nil, format: .table), "Showing 51-60 of 60.")
    }

    func testHintForAnEmptyMailboxAndForAPagePastTheEnd() {
        XCTAssertEqual(page(count: 0, totalCount: 0, hasMore: false).hint(account: nil, format: .table), "\"INBOX\" has no messages.")
        XCTAssertEqual(
            page(count: 0, totalCount: 60, page: 9, hasMore: false).hint(account: nil, format: .table),
            "Page 9 is past the end: \"INBOX\" has 60 messages, and the last page is 3."
        )
        XCTAssertEqual(
            page(count: 0, totalCount: 1, page: 2, hasMore: false).hint(account: nil, format: .table),
            "Page 2 is past the end: \"INBOX\" has 1 message, and the last page is 1."
        )
    }

    func testHintWithAFilterCountsMatchesAndKeepsTheFilterInTheNextPageCommand() throws {
        let filter = MessageFilter(unread: true, from: "Jane Doe", since: try day("2026-10-01"))
        XCTAssertEqual(
            page(filter: filter, count: 25, totalCount: 40, hasMore: true).hint(account: "work", format: .json),
            "Showing 1-25 of 40 matches. Next page: "
                + "iris list --account work --unread --from 'Jane Doe' --since 2026-10-01 --page 2 --format json"
        )
        XCTAssertEqual(
            page(filter: filter, count: 1, totalCount: 1, hasMore: false).hint(account: nil, format: .table),
            "Showing 1-1 of 1 match."
        )
    }

    func testHintWithAFilterForNoMatchesAndForAPagePastTheEnd() {
        let filter = MessageFilter(flagged: true)
        XCTAssertEqual(
            page(filter: filter, count: 0, totalCount: 0, hasMore: false).hint(account: nil, format: .table),
            "No message in \"INBOX\" matches the filter."
        )
        XCTAssertEqual(
            page(filter: filter, count: 0, totalCount: 60, page: 9, hasMore: false).hint(account: nil, format: .table),
            "Page 9 is past the end: 60 messages in \"INBOX\" match the filter, and the last page is 3."
        )
        XCTAssertEqual(
            page(filter: filter, count: 0, totalCount: 1, page: 2, hasMore: false).hint(account: nil, format: .table),
            "Page 2 is past the end: 1 message in \"INBOX\" matches the filter, and the last page is 1."
        )
    }

    func testListCommandHasEveryFilterOptionInHelpOrder() throws {
        let filter = MessageFilter(
            unread: true,
            flagged: true,
            from: "jane@example.com",
            subject: "Bob's plan",
            since: try day("2026-01-05"),
            before: try day("2026-02-01")
        )
        XCTAssertEqual(
            MessagePage.listCommand(account: nil, mailbox: "Sent", filter: filter, page: 3, limit: 10, format: .id),
            "iris list --mailbox Sent --unread --flagged --from jane@example.com --subject 'Bob'\\''s plan' "
                + "--since 2026-01-05 --before 2026-02-01 --page 3 --limit 10 --format id"
        )
    }

    func testListCommandLeavesOutDefaults() {
        XCTAssertEqual(
            MessagePage.listCommand(account: nil, mailbox: "INBOX", page: 1, limit: 25, format: .listDefault),
            "iris list"
        )
        XCTAssertEqual(
            MessagePage.listCommand(account: "my_gmail", mailbox: "[Gmail]/All Mail", page: 1, limit: 25, format: .listDefault),
            "iris list --account my_gmail --mailbox '[Gmail]/All Mail'"
        )
        XCTAssertEqual(
            MessagePage.listCommand(account: "work", mailbox: "Sent", page: 2, limit: 10, format: .jsonl),
            "iris list --account work --mailbox Sent --page 2 --limit 10 --format jsonl"
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
            irisID: id(42),
            from: MailAddress(name: "Jane Doe", address: "jane@example.com"),
            subject: "Hello",
            date: local,
            unread: false
        )
        XCTAssertEqual(summary.tableValues, ["work/INBOX/42", "2026-03-07 09:05", "Jane Doe", "", "Hello"])
        XCTAssertEqual(summary.idValue, "work/INBOX/42")
    }

    func testTableUnreadIsAHeavyBulletOrEmpty() {
        let unread = MessageSummary(irisID: id(1), from: nil, subject: "", date: nil, unread: true)
        let read = MessageSummary(irisID: id(2), from: nil, subject: "", date: nil, unread: false)
        XCTAssertEqual(unread.tableValues, ["work/INBOX/1", "", "", "●", ""])
        XCTAssertEqual(read.tableValues, ["work/INBOX/2", "", "", "", ""])
    }

    func testTableFromFallsBackToTheAddressAndEmptyValuesStayEmpty() {
        let noName = MessageSummary(
            irisID: id(1), from: MailAddress(name: nil, address: "bot@example.com"), subject: "", date: nil, unread: false
        )
        let emptyName = MessageSummary(
            irisID: id(2), from: MailAddress(name: "", address: "x@example.com"), subject: "", date: nil, unread: false
        )
        let noSender = MessageSummary(irisID: id(3), from: nil, subject: "", date: nil, unread: false)
        XCTAssertEqual(noName.tableValues, ["work/INBOX/1", "", "bot@example.com", "", ""])
        XCTAssertEqual(emptyName.tableValues, ["work/INBOX/2", "", "x@example.com", "", ""])
        XCTAssertEqual(noSender.tableValues, ["work/INBOX/3", "", "", "", ""])
    }

    func testTableCellsAreOneLine() {
        let summary = MessageSummary(
            irisID: id(1),
            from: MailAddress(name: "Jane\tDoe", address: "j@example.com"),
            subject: "Long\r\n subject",
            date: nil,
            unread: false
        )
        XCTAssertEqual(summary.tableValues, ["work/INBOX/1", "", "Jane Doe", "", "Long  subject"])
    }

    func testJSONHasTheIrisIDAsOneStringTheFullSenderAnISO8601DateAndUnread() throws {
        let summary = MessageSummary(
            irisID: id(101, mailbox: "[Gmail]/All Mail"),
            from: MailAddress(name: "Jane Doe", address: "jane@example.com"),
            subject: "Hi",
            date: sampleDate,
            unread: true
        )
        XCTAssertEqual(
            try OutputFormatter.render([summary], format: .jsonl),
            #"{"date":"2026-10-24T20:21:18Z","from":{"address":"jane@example.com","name":"Jane Doe"},"#
                + #""irisID":"work/[Gmail]/All Mail/101","subject":"Hi","unread":true}"# + "\n"
        )
    }

    func testTableColumnsAndIDFormat() throws {
        let rows = [
            MessageSummary(irisID: id(7), from: nil, subject: "Hi", date: nil, unread: true),
            MessageSummary(irisID: id(12, mailbox: "Sent Items"), from: nil, subject: "Re: Hi", date: nil, unread: false),
        ]
        XCTAssertEqual(try OutputFormatter.render(rows, format: .table), """
        IRIS ID             DATE  FROM  UNREAD  SUBJECT
        work/INBOX/7                         ●  Hi
        work/Sent Items/12                      Re: Hi

        """)
        XCTAssertEqual(try OutputFormatter.render(rows, format: .id), "work/INBOX/7\nwork/Sent Items/12\n")
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
            #"{"attributes":["\\Sent"],"name":"Sent"}"# + "\n"
        )
        XCTAssertEqual(try OutputFormatter.render(mailboxes, format: .id), "INBOX\nSent\n[Gmail]/All Mail\n")
    }

    // MARK: - AccountCheck

    func testCheckReportHasOneFactPerLineAndNoPassword() {
        let account = Account(
            name: "work", host: "imap.zoho.com", port: 993, username: "me@example.com",
            authentication: .password("hunter2")
        )
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
