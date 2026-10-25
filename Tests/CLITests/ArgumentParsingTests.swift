import XCTest
@testable import IrisKit
@testable import iris

final class ArgumentParsingTests: XCTestCase {
    func testAccountsDefaultsToTableFormat() throws {
        XCTAssertEqual(try Accounts.parse([]).format, .table)
    }

    func testAccountsParsesFormat() throws {
        XCTAssertEqual(try Accounts.parse(["--format", "json"]).format, .json)
    }

    func testAccountOptionsParseShortAndLongNames() throws {
        XCTAssertEqual(try AccountOptions.parse(["--account", "work"]).account, "work")
        XCTAssertEqual(try AccountOptions.parse(["-a", "work"]).account, "work")
        XCTAssertNil(try AccountOptions.parse([]).account)
    }

    func testCheckTakesTheAccountOption() throws {
        XCTAssertNil(try Check.parse([]).accountOptions.account)
        XCTAssertEqual(try Check.parse(["--account", "work"]).accountOptions.account, "work")
    }

    func testMailboxesDefaultsToTableFormat() throws {
        let command = try Mailboxes.parse([])
        XCTAssertEqual(command.format, .table)
        XCTAssertNil(command.accountOptions.account)
    }

    func testMailboxesParsesFormatAndAccount() throws {
        let command = try Mailboxes.parse(["--format", "jsonl", "-a", "work"])
        XCTAssertEqual(command.format, .jsonl)
        XCTAssertEqual(command.accountOptions.account, "work")
    }

    func testListDefaults() throws {
        let command = try List.parse([])
        XCTAssertEqual(command.mailbox, "INBOX")
        XCTAssertEqual(command.page, 1)
        XCTAssertEqual(command.limit, 25)
        XCTAssertEqual(command.format, .table)
        XCTAssertNil(command.accountOptions.account)
        XCTAssertEqual(command.filter, MessageFilter())
    }

    func testListParsesEveryOption() throws {
        let command = try List.parse([
            "--mailbox", "[Gmail]/All Mail", "--page", "3", "--limit", "10", "--format", "id", "--account", "personal",
            "--unread", "--flagged", "--from", "jane@example.com", "--subject", "Q4 plan",
            "--since", "2026-10-01", "--before", "2026-11-01",
        ])
        XCTAssertEqual(command.mailbox, "[Gmail]/All Mail")
        XCTAssertEqual(command.page, 3)
        XCTAssertEqual(command.limit, 10)
        XCTAssertEqual(command.format, .id)
        XCTAssertEqual(command.accountOptions.account, "personal")
        XCTAssertEqual(command.filter, MessageFilter(
            unread: true,
            flagged: true,
            from: "jane@example.com",
            subject: "Q4 plan",
            since: try CalendarDay(parsing: "2026-10-01"),
            before: try CalendarDay(parsing: "2026-11-01")
        ))
    }

    /// The next-page hint writes every option as text, so the command must parse back to the same options.
    /// The values need no shell quoting: `parse` gets the words with no shell to remove the quotes.
    func testTheNextPageCommandParsesBackToTheSameOptions() throws {
        let filter = MessageFilter(
            unread: true,
            flagged: true,
            from: "jane@example.com",
            subject: "Q4",
            since: try CalendarDay(parsing: "2026-10-01"),
            before: try CalendarDay(parsing: "2026-11-01")
        )
        let command = MessagePage.listCommand(
            account: "work", mailbox: "Archive", filter: filter, page: 3, limit: 10, format: .jsonl
        )
        let words = command.split(separator: " ").map(String.init)
        XCTAssertEqual(Array(words.prefix(2)), ["iris", "list"])

        let list = try List.parse(Array(words.dropFirst(2)))

        XCTAssertEqual(list.accountOptions.account, "work")
        XCTAssertEqual(list.mailbox, "Archive")
        XCTAssertEqual(list.filter, filter)
        XCTAssertEqual(list.page, 3)
        XCTAssertEqual(list.limit, 10)
        XCTAssertEqual(list.format, .jsonl)
    }

    func testListFilterFlagsTakeNoValue() throws {
        XCTAssertEqual(try List.parse(["--unread"]).filter, MessageFilter(unread: true))
        XCTAssertEqual(try List.parse(["--flagged"]).filter, MessageFilter(flagged: true))
        XCTAssertThrowsError(try List.parse(["--unread", "yes"]))
    }

    func testListExplainsABadDate() {
        for option in ["--since", "--before"] {
            XCTAssertThrowsError(try List.parse([option, "10/24/2026"])) { error in
                let message = List.message(for: error)
                XCTAssertTrue(message.contains("\"10/24/2026\" is not a date"), message)
                XCTAssertTrue(message.contains("YYYY-MM-DD"), message)
            }
        }
    }

    func testListRejectsAPageThatIsNotANumber() {
        XCTAssertThrowsError(try List.parse(["--page", "two"]))
    }

    func testListRejectsAnUnknownFormat() {
        XCTAssertThrowsError(try List.parse(["--format", "csv"]))
    }

    func testShowDefaults() throws {
        let command = try Show.parse(["work/INBOX/42"])
        XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertEqual(command.body, .auto)
        XCTAssertEqual(command.format, .markdown)
    }

    func testShowParsesEveryOption() throws {
        let command = try Show.parse(["personal/[Gmail]/Sent Mail/7", "--body", "text", "--format", "raw"])
        XCTAssertEqual(command.irisID, IrisID(account: "personal", mailbox: "[Gmail]/Sent Mail", uid: 7))
        XCTAssertEqual(command.body, .text)
        XCTAssertEqual(command.format, .raw)
    }

    func testShowNeedsAFullIrisID() {
        XCTAssertThrowsError(try Show.parse([]))
        XCTAssertThrowsError(try Show.parse(["42"]))
        XCTAssertThrowsError(try Show.parse(["INBOX/42"]))
        XCTAssertThrowsError(try Show.parse(["work/INBOX/abc"]))
    }

    func testShowExplainsABadIrisID() {
        XCTAssertThrowsError(try Show.parse(["42"])) { error in
            let message = Show.message(for: error)
            XCTAssertTrue(message.contains("\"42\" is not an iris ID"), message)
            XCTAssertTrue(message.contains("<account>/<mailbox>/<UID>"), message)
        }
    }

    func testShowHasNoAccountOrMailboxOption() {
        // The iris ID names both.
        XCTAssertThrowsError(try Show.parse(["work/INBOX/42", "--account", "work"]))
        XCTAssertThrowsError(try Show.parse(["work/INBOX/42", "--mailbox", "INBOX"]))
    }

    func testThreadDefaults() throws {
        let command = try ThreadCommand.parse(["work/INBOX/42"])
        XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertEqual(command.body, .auto)
        XCTAssertEqual(command.format, .markdown)
    }

    func testThreadParsesEveryOption() throws {
        let command = try ThreadCommand.parse(["personal/[Gmail]/Sent Mail/7", "--body", "html", "--format", "json"])
        XCTAssertEqual(command.irisID, IrisID(account: "personal", mailbox: "[Gmail]/Sent Mail", uid: 7))
        XCTAssertEqual(command.body, .html)
        XCTAssertEqual(command.format, .json)
    }

    func testThreadParsesTheJSONLinesAndIDFormats() throws {
        XCTAssertEqual(try ThreadCommand.parse(["work/INBOX/42", "--format", "jsonl"]).format, .jsonl)
        XCTAssertEqual(try ThreadCommand.parse(["work/INBOX/42", "--format", "id"]).format, .id)
        XCTAssertThrowsError(try ThreadCommand.parse(["work/INBOX/42", "--format", "table"]), "no table: a thread is not rows")
    }

    func testThreadHasNoRawFormat() {
        // A thread is several messages, so there is no single message source to print.
        XCTAssertThrowsError(try ThreadCommand.parse(["work/INBOX/42", "--format", "raw"]))
    }

    func testThreadNeedsAFullIrisIDAndExplainsABadOne() {
        XCTAssertThrowsError(try ThreadCommand.parse([]))
        XCTAssertThrowsError(try ThreadCommand.parse(["INBOX/42"]))
        XCTAssertThrowsError(try ThreadCommand.parse(["42"])) { error in
            let message = ThreadCommand.message(for: error)
            XCTAssertTrue(message.contains("\"42\" is not an iris ID"), message)
            XCTAssertTrue(message.contains("<account>/<mailbox>/<UID>"), message)
        }
    }

    func testThreadHasNoAccountOrMailboxOption() {
        // The iris ID names both.
        XCTAssertThrowsError(try ThreadCommand.parse(["work/INBOX/42", "--account", "work"]))
        XCTAssertThrowsError(try ThreadCommand.parse(["work/INBOX/42", "--mailbox", "INBOX"]))
    }

    func testReadAndUnreadTakeOneIrisID() throws {
        XCTAssertEqual(
            try Read.parse(["personal/[Gmail]/All Mail/7"]).irisID,
            IrisID(account: "personal", mailbox: "[Gmail]/All Mail", uid: 7)
        )
        XCTAssertEqual(try Unread.parse(["work/INBOX/42"]).irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
    }

    func testReadAndUnreadNeedAFullIrisID() {
        for parse in [{ _ = try Read.parse($0) }, { _ = try Unread.parse($0) }] as [([String]) throws -> Void] {
            XCTAssertThrowsError(try parse([]))
            XCTAssertThrowsError(try parse(["42"]))
            XCTAssertThrowsError(try parse(["INBOX/42"]))
            XCTAssertThrowsError(try parse(["work/INBOX/42", "work/INBOX/43"]))
        }
        XCTAssertThrowsError(try Read.parse(["42"])) { error in
            XCTAssertTrue(Read.message(for: error).contains("\"42\" is not an iris ID"), Read.message(for: error))
        }
    }

    func testReadAndUnreadHaveNoAccountOrMailboxOption() {
        // The iris ID names both.
        XCTAssertThrowsError(try Read.parse(["work/INBOX/42", "--account", "work"]))
        XCTAssertThrowsError(try Unread.parse(["work/INBOX/42", "--mailbox", "INBOX"]))
    }

    func testAuthLoginParsesWithAndWithoutAnAccount() throws {
        let plain = try XCTUnwrap(try Iris.parseAsRoot(["auth", "login"]) as? Auth.Login)
        XCTAssertNil(plain.accountOptions.account)
        let named = try XCTUnwrap(try Iris.parseAsRoot(["auth", "login", "--account", "personal"]) as? Auth.Login)
        XCTAssertEqual(named.accountOptions.account, "personal")
        XCTAssertEqual(try Auth.Login.parse(["-a", "personal"]).accountOptions.account, "personal")
    }

    func testAuthStatusDefaultsToEveryAccountAndTableFormat() throws {
        let command = try Auth.Status.parse([])
        XCTAssertNil(command.account, "no --account checks every Google account")
        XCTAssertEqual(command.format, .table)
        XCTAssertEqual(try Auth.Status.parse(["-a", "personal"]).account, "personal")
        XCTAssertEqual(try Auth.Status.parse(["--format", "jsonl"]).format, .jsonl)
        XCTAssertThrowsError(try Auth.Status.parse(["--format", "csv"]))
    }

    func testAuthLoginTakesNoOtherArguments() {
        XCTAssertThrowsError(try Iris.parseAsRoot(["auth", "login", "personal"]))
        XCTAssertThrowsError(try Iris.parseAsRoot(["auth", "logout"]))
    }

    func testDraftDefaults() throws {
        let command = try Draft.parse(["work/INBOX/42"])
        XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertNil(command.body)
        XCTAssertNil(command.file)
        XCTAssertFalse(command.all)
        XCTAssertFalse(command.noQuote, "the original is quoted by default")
    }

    func testDraftTakesTheReplyAsAnArgument() throws {
        let command = try Draft.parse(["personal/[Gmail]/All Mail/7", "Thanks, *Jane*!", "--all", "--no-quote"])
        XCTAssertEqual(command.irisID, IrisID(account: "personal", mailbox: "[Gmail]/All Mail", uid: 7))
        XCTAssertEqual(command.body, "Thanks, *Jane*!")
        XCTAssertTrue(command.all)
        XCTAssertTrue(command.noQuote)
    }

    func testDraftTakesAFileWithShortAndLongNames() throws {
        XCTAssertEqual(try Draft.parse(["work/INBOX/42", "-F", "reply.md"]).file, "reply.md")
        XCTAssertEqual(try Draft.parse(["work/INBOX/42", "--file", "reply.md"]).file, "reply.md")
        XCTAssertEqual(try Draft.parse(["work/INBOX/42", "-F", "-"]).file, "-", "-F - reads stdin")
    }

    /// The parser accepts both, so that DraftBody can say what to do instead.
    func testDraftParsesAnArgumentAndAFileTogether() throws {
        let command = try Draft.parse(["work/INBOX/42", "Thanks!", "-F", "reply.md"])
        XCTAssertEqual(command.body, "Thanks!")
        XCTAssertEqual(command.file, "reply.md")
    }

    func testDraftNeedsAFullIrisIDAndHasNoAccountOption() {
        XCTAssertThrowsError(try Draft.parse([]))
        XCTAssertThrowsError(try Draft.parse(["42", "Thanks!"]))
        XCTAssertThrowsError(try Draft.parse(["work/INBOX/42", "--account", "work"]), "the iris ID names the account")
        XCTAssertThrowsError(try Draft.parse(["work/INBOX/42", "--quote"]), "only --no-quote exists")
    }

    func testDraftExplainsABadIrisID() {
        XCTAssertThrowsError(try Draft.parse(["INBOX/42"])) { error in
            let message = Draft.message(for: error)
            XCTAssertTrue(message.contains("\"INBOX/42\" is not an iris ID"), message)
        }
    }

    /// ArgumentParser lists an option's values itself, so our help strings no longer list them too.
    func testHelpNoLongerHasTheOldValueLists() {
        let oldPhrases = ["table, json, jsonl, or id", "markdown, json, or raw", "auto (HTML", "text, or html"]
        let helps = [
            Accounts.helpMessage(columns: 1000),
            Mailboxes.helpMessage(columns: 1000),
            List.helpMessage(columns: 1000),
            Show.helpMessage(columns: 1000),
            ThreadCommand.helpMessage(columns: 1000),
        ]
        for help in helps {
            for phrase in oldPhrases {
                XCTAssertFalse(help.contains(phrase), "\(phrase) in \(help)")
            }
        }
    }
}
