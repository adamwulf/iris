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
            "--unread", "--flagged", "--from", "jane@example.com", "--to", "bob@example.com",
            "--subject", "Q4 plan", "--search", "budget",
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
            to: "bob@example.com",
            subject: "Q4 plan",
            search: "budget",
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
            to: "bob@example.com",
            subject: "Q4",
            search: "budget",
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
        XCTAssertFalse(command.full, "the quoted history is hidden by default")
        XCTAssertEqual(command.format, .markdown)
    }

    func testShowParsesEveryOption() throws {
        let command = try Show.parse(["personal/[Gmail]/Sent Mail/7", "--body", "text", "--full", "--format", "raw"])
        XCTAssertEqual(command.irisID, IrisID(account: "personal", mailbox: "[Gmail]/Sent Mail", uid: 7))
        XCTAssertEqual(command.body, .text)
        XCTAssertTrue(command.full)
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
        XCTAssertFalse(command.full, "the quoted history is hidden by default")
        XCTAssertEqual(command.format, .markdown)
    }

    func testThreadParsesEveryOption() throws {
        let command = try ThreadCommand.parse(["personal/[Gmail]/Sent Mail/7", "--body", "html", "--full", "--format", "json"])
        XCTAssertEqual(command.irisID, IrisID(account: "personal", mailbox: "[Gmail]/Sent Mail", uid: 7))
        XCTAssertEqual(command.body, .html)
        XCTAssertTrue(command.full)
        XCTAssertEqual(command.format, .json)
    }

    func testReadOnlyShowAndThreadTakeFull() throws {
        let show = try XCTUnwrap(try Iris.parseAsRoot(["ro", "show", "work/INBOX/42", "--full"]) as? Show)
        XCTAssertTrue(show.full)
        let thread = try XCTUnwrap(try Iris.parseAsRoot(["ro", "thread", "work/INBOX/42", "--full"]) as? ThreadCommand)
        XCTAssertTrue(thread.full)
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

    func testDraftReplyDefaults() throws {
        let command = try Draft.Reply.parse(["work/INBOX/42"])
        XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertNil(command.body)
        XCTAssertNil(command.file)
        XCTAssertFalse(command.all)
        XCTAssertFalse(command.noQuote, "the original is quoted by default")
        XCTAssertEqual(command.attach, [], "no attachments by default")
    }

    func testDraftReplyTakesTheReplyAsAnArgument() throws {
        let command = try Draft.Reply.parse(["personal/[Gmail]/All Mail/7", "Thanks, *Jane*!", "--all", "--no-quote"])
        XCTAssertEqual(command.irisID, IrisID(account: "personal", mailbox: "[Gmail]/All Mail", uid: 7))
        XCTAssertEqual(command.body, "Thanks, *Jane*!")
        XCTAssertTrue(command.all)
        XCTAssertTrue(command.noQuote)
    }

    /// Without `--`, a reply that starts with `-` (a Markdown list) reads as an option.
    func testDraftReplyTakesAReplyThatStartsWithADashAfterDoubleDash() throws {
        XCTAssertThrowsError(try Draft.Reply.parse(["work/INBOX/4821", "- yes"]))

        let command = try Draft.Reply.parse(["work/INBOX/4821", "--", "- yes\n- no"])
        XCTAssertEqual(command.body, "- yes\n- no")

        let withOptions = try Draft.Reply.parse(["work/INBOX/4821", "--all", "--no-quote", "--", "-- signed"])
        XCTAssertEqual(withOptions.body, "-- signed")
        XCTAssertTrue(withOptions.all)
        XCTAssertTrue(withOptions.noQuote)
    }

    func testDraftReplyTakesAFileWithShortAndLongNames() throws {
        XCTAssertEqual(try Draft.Reply.parse(["work/INBOX/42", "-F", "reply.md"]).file, "reply.md")
        XCTAssertEqual(try Draft.Reply.parse(["work/INBOX/42", "--file", "reply.md"]).file, "reply.md")
        XCTAssertEqual(try Draft.Reply.parse(["work/INBOX/42", "-F", "-"]).file, "-", "-F - reads stdin")
    }

    /// The parser accepts both, so that DraftBody can say what to do instead.
    func testDraftReplyParsesAnArgumentAndAFileTogether() throws {
        let command = try Draft.Reply.parse(["work/INBOX/42", "Thanks!", "-F", "reply.md"])
        XCTAssertEqual(command.body, "Thanks!")
        XCTAssertEqual(command.file, "reply.md")
    }

    func testDraftReplyTakesRepeatedAttachInOrder() throws {
        let command = try Draft.Reply.parse([
            "work/INBOX/42", "--attach", "q4.pdf", "Thanks!", "--attach=notes/My Notes.txt", "--all", "--attach", "q4.pdf",
        ])
        XCTAssertEqual(command.attach, ["q4.pdf", "notes/My Notes.txt", "q4.pdf"], "in order, repeats kept")
        XCTAssertEqual(command.body, "Thanks!")
        XCTAssertTrue(command.all)

        let withFile = try Draft.Reply.parse(["work/INBOX/42", "-F", "reply.md", "--attach", "q4.pdf"])
        XCTAssertEqual(withFile.file, "reply.md")
        XCTAssertEqual(withFile.attach, ["q4.pdf"])
    }

    /// Each --attach takes one path, so a second path is the reply, not another file.
    /// `DraftBody.read` then rejects a reply that names a file (`draftBodyNamesAFile`).
    func testDraftReplyAttachTakesOnePathEach() throws {
        let command = try Draft.Reply.parse(["work/INBOX/42", "--attach", "q4.pdf", "budget.xlsx"])
        XCTAssertEqual(command.attach, ["q4.pdf"])
        XCTAssertEqual(command.body, "budget.xlsx")

        XCTAssertThrowsError(try Draft.Reply.parse(["work/INBOX/42", "--attach"]), "--attach needs a path")
    }

    func testDraftReplyNeedsAFullIrisIDAndHasNoAccountOption() {
        XCTAssertThrowsError(try Draft.Reply.parse([]))
        XCTAssertThrowsError(try Draft.Reply.parse(["42", "Thanks!"]))
        XCTAssertThrowsError(try Draft.Reply.parse(["work/INBOX/42", "--account", "work"]), "the iris ID names the account")
        XCTAssertThrowsError(try Draft.Reply.parse(["work/INBOX/42", "--quote"]), "only --no-quote exists")
    }

    func testDraftReplyExplainsABadIrisID() {
        XCTAssertThrowsError(try Draft.Reply.parse(["INBOX/42"])) { error in
            let message = Draft.Reply.message(for: error)
            XCTAssertTrue(message.contains("\"INBOX/42\" is not an iris ID"), message)
        }
    }

    func testDraftSubcommandsParseFromTheRoot() throws {
        let reply = try XCTUnwrap(try Iris.parseAsRoot([
            "draft", "reply", "work/INBOX/42", "Thanks!", "--all", "--no-quote", "--attach", "report.pdf",
        ]) as? Draft.Reply)
        XCTAssertEqual(reply.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertEqual(reply.body, "Thanks!")
        XCTAssertTrue(reply.all)
        XCTAssertTrue(reply.noQuote)
        XCTAssertEqual(reply.attach, ["report.pdf"])

        let update = try XCTUnwrap(try Iris.parseAsRoot([
            "draft", "update", "personal/[Gmail]/Drafts/7", "Replacement *body*.",
        ]) as? Draft.Update)
        XCTAssertEqual(update.irisID, IrisID(account: "personal", mailbox: "[Gmail]/Drafts", uid: 7))
        XCTAssertEqual(update.body, "Replacement *body*.")
        XCTAssertNil(update.file)
    }

    func testDraftRejectsTheOldBareSyntax() {
        for arguments in [
            ["draft", "work/INBOX/42"],
            ["draft", "work/INBOX/42", "Thanks!"],
            ["draft", "work/INBOX/42", "-F", "-"],
            ["draft", "work/INBOX/42", "Thanks!", "--all"],
        ] {
            XCTAssertThrowsError(try Iris.parseAsRoot(arguments), "\(arguments)")
        }
    }

    func testDraftUpdateDefaultsToReadingStdin() throws {
        let command = try Draft.Update.parse(["work/Drafts/42"])
        XCTAssertEqual(command.irisID, IrisID(account: "work", mailbox: "Drafts", uid: 42))
        XCTAssertNil(command.body)
        XCTAssertNil(command.file)
    }

    func testDraftUpdateTakesAFileWithShortAndLongNames() throws {
        for option in ["-F", "--file"] {
            let command = try Draft.Update.parse(["work/Drafts/42", option, "body.md"])
            XCTAssertNil(command.body)
            XCTAssertEqual(command.file, "body.md")
        }
        XCTAssertEqual(try Draft.Update.parse(["work/Drafts/42", "-F", "-"]).file, "-")
    }

    func testDraftUpdateTakesABodyThatStartsWithADashAfterDoubleDash() throws {
        XCTAssertThrowsError(try Draft.Update.parse(["work/Drafts/42", "- yes"]))
        XCTAssertEqual(try Draft.Update.parse(["work/Drafts/42", "--", "- yes\n- no"]).body, "- yes\n- no")
    }

    /// DraftBody reports the conflicting sources with a useful next step.
    func testDraftUpdateParsesAnArgumentAndAFileTogether() throws {
        let command = try Draft.Update.parse(["work/Drafts/42", "Replacement", "-F", "body.md"])
        XCTAssertEqual(command.body, "Replacement")
        XCTAssertEqual(command.file, "body.md")
    }

    func testDraftUpdateRejectsReplyOptions() {
        for options in [["--all"], ["--no-quote"], ["--attach", "report.pdf"]] {
            XCTAssertThrowsError(try Iris.parseAsRoot(["draft", "update", "work/Drafts/42", "Replacement"] + options))
        }
    }

    func testDraftUpdateNeedsAFullIrisIDAndHasNoAccountOrMailboxOption() {
        XCTAssertThrowsError(try Draft.Update.parse([]))
        XCTAssertThrowsError(try Draft.Update.parse(["42", "Replacement"]))
        XCTAssertThrowsError(try Draft.Update.parse(["work/Drafts/42", "--account", "work"]))
        XCTAssertThrowsError(try Draft.Update.parse(["work/Drafts/42", "--mailbox", "Drafts"]))
        XCTAssertThrowsError(try Draft.Update.parse(["work/Drafts/42", "Replacement", "extra"]))
        XCTAssertThrowsError(try Draft.Update.parse(["INBOX/42"])) { error in
            let message = Draft.Update.message(for: error)
            XCTAssertTrue(message.contains("\"INBOX/42\" is not an iris ID"), message)
        }
    }

    func testDownloadTakesAnIrisIDAndAnAttachmentID() throws {
        let command = try Download.parse(["personal/[Gmail]/All Mail/7", "1.2"])
        XCTAssertEqual(command.arguments.irisID, IrisID(account: "personal", mailbox: "[Gmail]/All Mail", uid: 7))
        XCTAssertEqual(command.arguments.attachmentID.components, [1, 2])
        XCTAssertNil(command.output, "without -o, the bytes go to stdout")
    }

    func testDownloadTakesTheOutputPathWithShortAndLongNames() throws {
        XCTAssertEqual(try Download.parse(["work/INBOX/42", "2", "-o", "report.pdf"]).output, "report.pdf")
        XCTAssertEqual(try Download.parse(["work/INBOX/42", "2", "--output", "~/Downloads"]).output, "~/Downloads")
        XCTAssertEqual(try Download.parse(["-o", "x", "work/INBOX/42", "2"]).output, "x")
    }

    func testReadOnlyDownloadTakesTheSameArgumentsAndNoOutputPath() throws {
        let command = try ReadOnlyDownload.parse(["work/INBOX/42", "2"])
        XCTAssertEqual(command.arguments.irisID, IrisID(account: "work", mailbox: "INBOX", uid: 42))
        XCTAssertEqual(command.arguments.attachmentID.components, [2])
        XCTAssertThrowsError(try ReadOnlyDownload.parse(["work/INBOX/42", "2", "-o", "x"]))
        XCTAssertThrowsError(try ReadOnlyDownload.parse(["work/INBOX/42", "2", "--output", "x"]))
    }

    func testDownloadNeedsBothIDsAndHasNoAccountOption() {
        for parse in [{ try Download.parse($0) }, { try ReadOnlyDownload.parse($0) }] as [([String]) throws -> Any] {
            XCTAssertThrowsError(try parse([]))
            XCTAssertThrowsError(try parse(["work/INBOX/42"]), "the attachment ID is required")
            XCTAssertThrowsError(try parse(["work/INBOX/42", "2", "3"]), "one attachment at a time")
            XCTAssertThrowsError(try parse(["work/INBOX/42", "2", "--account", "work"]), "the iris ID names the account")
        }
    }

    func testDownloadExplainsABadIrisIDAndABadAttachmentID() {
        XCTAssertThrowsError(try Download.parse(["INBOX/42", "2"])) { error in
            let message = Download.message(for: error)
            XCTAssertTrue(message.contains("\"INBOX/42\" is not an iris ID"), message)
        }
        for bad in ["0", "1.", "a", "-1"] {
            XCTAssertThrowsError(try Download.parse(["work/INBOX/42", "--", bad])) { error in
                let message = Download.message(for: error)
                XCTAssertTrue(message.contains("\"\(bad)\" is not an attachment ID"), message)
            }
        }
        XCTAssertThrowsError(try ReadOnlyDownload.parse(["work/INBOX/42", "x.2"])) { error in
            let message = ReadOnlyDownload.message(for: error)
            XCTAssertTrue(message.contains("\"x.2\" is not an attachment ID"), message)
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
