import Foundation
import XCTest
@testable import IrisKit

/// `MailReader.thread` over a fake server that holds whole mailboxes. The
/// fake searches as Zoho did in the 2026-10-24 probes unless a test picks
/// RFC 3501 rules (`FakeMailClient.SearchRules`): HEADER In-Reply-To and
/// References never match, so iris must find the replies through the subject.
final class MailReaderThreadTests: XCTestCase {
    private typealias Message = FakeMailClient.Message
    private typealias SearchRules = FakeMailClient.SearchRules

    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com", password: "secret"
    )

    /// Zoho's mailboxes, as LIST gave them on 2026-10-24: two `\Sent`, and no `\All`.
    private let zohoMailboxes = [
        MailboxInfo(name: "INBOX", attributes: []),
        MailboxInfo(name: "Drafts", attributes: [#"\Drafts"#]),
        MailboxInfo(name: "Sent", attributes: [#"\Sent"#]),
        MailboxInfo(name: "Sent Messages", attributes: [#"\Sent"#]),
        MailboxInfo(name: "Archive", attributes: [#"\Archive"#]),
        MailboxInfo(name: "Junk", attributes: [#"\Junk"#]),
        MailboxInfo(name: "Trash", attributes: [#"\Trash"#]),
    ]

    /// Gmail's mailboxes: `\All` holds every message but Spam and Trash, and a
    /// label (Projects) is a mailbox without a special-use attribute.
    private let gmailMailboxes = [
        MailboxInfo(name: "INBOX", attributes: []),
        MailboxInfo(name: "Projects", attributes: []),
        MailboxInfo(name: "[Gmail]", attributes: []),
        MailboxInfo(name: "[Gmail]/All Mail", attributes: [#"\All"#]),
        MailboxInfo(name: "[Gmail]/Drafts", attributes: [#"\Drafts"#]),
        MailboxInfo(name: "[Gmail]/Sent Mail", attributes: [#"\Sent"#]),
        MailboxInfo(name: "[Gmail]/Spam", attributes: [#"\Junk"#]),
        MailboxInfo(name: "[Gmail]/Trash", attributes: [#"\Trash"#]),
    ]

    private func reader(_ fake: FakeMailClient) -> MailReader {
        MailReader(account: account, makeClient: { _ in fake })
    }

    /// A fake server with the `mailboxes` LIST gives (Zoho's by default),
    /// each empty unless `messages` fills it. `messages` can also fill a
    /// mailbox that LIST does not give.
    private func server(
        _ messages: [String: [UInt32: Message]],
        mailboxes: [MailboxInfo]? = nil,
        rules: SearchRules = .zoho,
        refusesNonASCII: Bool = false,
        rawMessageErrors: [UInt32: any Error] = [:],
        errors: [FakeMailClient.Method: any Error] = [:]
    ) -> FakeMailClient {
        let listed = mailboxes ?? zohoMailboxes
        var all = Dictionary(uniqueKeysWithValues: listed.map { ($0.name, [UInt32: Message]()) })
        all.merge(messages) { _, filled in filled }
        return FakeMailClient(
            mailboxes: listed,
            mailboxMessages: all,
            searchRules: rules,
            refusesNonASCII: refusesNonASCII,
            rawMessageErrors: rawMessageErrors,
            errors: errors
        )
    }

    /// The texts of each SUBJECT search in `calls`, in order.
    private func subjectSearches(_ calls: [FakeMailClient.Call]) -> [[String]] {
        calls.compactMap { call in
            if case .searchSubject(let texts) = call { return texts } else { return nil }
        }
    }

    /// The IDs of each Message-ID search in `calls`, in order.
    private func messageIDSearches(_ calls: [FakeMailClient.Call]) -> [[String]] {
        calls.compactMap { call in
            if case .searchMessageIDs(let ids) = call { return ids } else { return nil }
        }
    }

    /// `<name@example.com>`.
    private func id(_ name: String) -> String {
        "<\(name)@example.com>"
    }

    /// Noon UTC on day `day` of some month.
    private func day(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400)
    }

    /// The message `name` (its Message-ID is `<name@example.com>`), sent on
    /// `day` and received 30 seconds later, replying to `parent` with
    /// `references`, by name.
    private func message(
        _ name: String?,
        subject: String = "Re: Budget",
        day: Int,
        replyTo parent: String? = nil,
        references: [String] = []
    ) -> Message {
        Message(
            messageID: name.map(id),
            inReplyTo: parent.map(id),
            references: references.map(id),
            subject: subject,
            date: self.day(day),
            internalDate: self.day(day).addingTimeInterval(30)
        )
    }

    /// The iris IDs of the thread of `start`, an iris ID as text.
    private func thread(_ fake: FakeMailClient, from start: String) async throws -> [String] {
        try await reader(fake).thread(try IrisID(parsing: start)).map(\.irisID.description)
    }

    /// The mailboxes of the first search round, in order: the EXAMINEs, the
    /// one of the input mailbox first, until one repeats.
    private func firstRoundMailboxes(_ calls: [FakeMailClient.Call]) -> [String] {
        var names: [String] = []
        for case .examine(let name) in calls {
            if names.contains(name) {
                break
            }
            names.append(name)
        }
        return names
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

    // MARK: - The fake

    /// The thread tests are only as good as the fake, so check that it answers as Zoho did.
    func testTheFakeSearchesAsZohoDid() async throws {
        let fake = server(["INBOX": [
            1: message("a", subject: "Josh ←→ Anthony: Introduction for AI application work", day: 1),
            2: message("b", subject: "Re: Josh ←→ Anthony: Introduction for AI application work", day: 2),
            3: message("c", subject: "Don't lose your bill’s Vanguard's single-use code", day: 3),
        ]])
        _ = try await fake.examine(mailbox: "INBOX")

        func subject(_ texts: String...) async throws -> Set<UInt32> {
            Set(try await fake.searchUIDs(subjectContainingAll: texts))
        }
        let byMessageID = try await fake.searchUIDs(messageIDs: [id("a")])
        let withoutBrackets = try await fake.searchUIDs(messageIDs: ["a@example.com"])
        let partOfAnID = try await fake.searchUIDs(messageIDs: ["a@example"])

        XCTAssertEqual(byMessageID, [1])
        XCTAssertEqual(withoutBrackets, [1])
        XCTAssertEqual(partOfAnID, [], "Zoho matches the whole ID")
        let whole = try await subject("josh ←→ anthony: introduction for ai application work")
        XCTAssertEqual(whole, [1, 2], "text that is not ASCII is accepted; the short word is ignored")
        let wordsAnded = try await subject("introduction", "application", "anthony", "josh", "work")
        XCTAssertEqual(wordsAnded, [1, 2])
        let withAShortWord = try await subject("introduction", "ai")
        XCTAssertEqual(withAShortWord, [], "a key of only a short word finds nothing")
        let partOfAWord = try await subject("introduct")
        XCTAssertEqual(partOfAWord, [], "whole words only")
        let curly = try await subject("bill")
        XCTAssertEqual(curly, [3], "the curly apostrophe ends a word")
        let contraction = try await subject("don")
        XCTAssertEqual(contraction, [], "a word with an ASCII apostrophe stays whole")
        let possessive = try await subject("vanguard")
        XCTAssertEqual(possessive, [3])
        let hyphen = try await subject("single", "use")
        XCTAssertEqual(hyphen, [3])
    }

    // MARK: - The walk

    func testAChainWhereEachReplyNamesOnlyItsParentIsFoundFromEveryMessage() async throws {
        // iPhone Mail puts only the parent in References.
        let expected = ["work/INBOX/10", "work/Sent/20", "work/INBOX/12", "work/Sent/21"]
        for rules in SearchRules.allCases {
            let fake = server([
                "INBOX": [
                    10: message("a", subject: "Budget", day: 1),
                    12: message("c", day: 3, replyTo: "b", references: ["b"]),
                ],
                "Sent": [
                    20: message("b", day: 2, replyTo: "a", references: ["a"]),
                    21: message("d", day: 4, replyTo: "c", references: ["c"]),
                ],
            ], rules: rules)

            for start in expected {
                let found = try await thread(fake, from: start)
                XCTAssertEqual(found, expected, "\(rules) rules, from \(start)")
            }
        }
    }

    func testBranchesGiveTheSameThreadFromEachMessage() async throws {
        // A has two replies, B and C, each with In-Reply-To A. From B, C is found through A.
        let expected = ["work/INBOX/10", "work/Sent/20", "work/INBOX/11"]
        for rules in SearchRules.allCases {
            let fake = server([
                "INBOX": [
                    10: message("a", subject: "Budget", day: 1),
                    11: message("c", day: 3, replyTo: "a", references: ["a"]),
                ],
                "Sent": [20: message("b", day: 2, replyTo: "a", references: ["a"])],
            ], rules: rules)

            let fromA = try await thread(fake, from: "work/INBOX/10")
            let fromB = try await thread(fake, from: "work/Sent/20")
            let fromC = try await thread(fake, from: "work/INBOX/11")

            XCTAssertEqual(fromA, expected, "\(rules) rules")
            XCTAssertEqual(fromB, fromA, "\(rules) rules")
            XCTAssertEqual(fromC, fromA, "\(rules) rules")
        }
    }

    func testASubjectChangeStartsANewThread() async throws {
        // An Outlook user replied to an old email and changed the subject, so
        // References names the old conversation. A later message that changes
        // the subject back (e) is left out, and a message linked to the thread
        // only through e (x) is left out too: e's IDs are not followed.
        let old = ["work/INBOX/1", "work/INBOX/2", "work/Sent/3"]
        let new = ["work/INBOX/5", "work/Sent/6", "work/INBOX/7"]
        for rules in SearchRules.allCases {
            let fake = server([
                "INBOX": [
                    1: message("o1", subject: "Budget", day: 1),
                    2: message("o2", subject: "Re: Budget", day: 2, replyTo: "o1", references: ["o1"]),
                    5: message("n1", subject: "Impact Champion Role", day: 5, replyTo: "o2", references: ["o1", "o2"]),
                    7: message("n3", subject: "RE: Impact Champion Role", day: 7, replyTo: "n2", references: ["o1", "o2", "n1", "n2"]),
                    8: message("e", subject: "Budget again", day: 8, replyTo: "n3", references: ["n1", "n2", "n3"]),
                ],
                "Sent": [
                    3: message("o3", subject: "Re: Budget", day: 3, replyTo: "o2", references: ["o1", "o2"]),
                    6: message("n2", subject: "Re: Impact Champion Role", day: 6, replyTo: "n1", references: ["o1", "o2", "n1"]),
                ],
                "Archive": [30: message("x", subject: "Re: Impact Champion Role", day: 9, replyTo: "e", references: ["e"])],
            ], rules: rules)

            for start in new {
                let found = try await thread(fake, from: start)
                XCTAssertEqual(found, new, "\(rules) rules, from \(start)")
            }
            let fromOld = try await thread(fake, from: "work/INBOX/1")
            XCTAssertEqual(fromOld, old, "\(rules) rules: the old thread does not take the new one")
        }
    }

    func testRepliesWithListAndGatewayTagsStayInTheThread() async throws {
        // Mailman 3 writes "[list] Re: x"; corporate gateways add "[EXTERNAL]".
        let expected = ["work/INBOX/1", "work/INBOX/2", "work/Sent/3"]
        for rules in SearchRules.allCases {
            let fake = server([
                "INBOX": [
                    1: message("a", subject: "[list] Budget", day: 1),
                    2: message("b", subject: "[list] Re: Budget", day: 2, replyTo: "a", references: ["a"]),
                ],
                "Sent": [3: message("c", subject: "Re: [EXTERNAL] Budget", day: 3, replyTo: "b", references: ["a", "b"])],
            ], rules: rules)

            for start in expected {
                let found = try await thread(fake, from: start)
                XCTAssertEqual(found, expected, "\(rules) rules, from \(start)")
            }
        }
    }

    func testAReplyWithoutAMessageIDIsShown() async throws {
        let fake = server([
            "INBOX": [10: message("a", subject: "Budget", day: 1)],
            "Sent": [20: message(nil, day: 2, replyTo: "a", references: ["a"])],
        ])

        let found = try await thread(fake, from: "work/INBOX/10")

        XCTAssertEqual(found, ["work/INBOX/10", "work/Sent/20"])
    }

    // MARK: - Copies in several mailboxes

    func testACopyInSeveralMailboxesIsShownOnceFromAFixedMailboxOrder() async throws {
        // On Gmail a message is in INBOX or Sent Mail, in All Mail, and in each label.
        // The order is INBOX, then Sent, Drafts, Archive, All, then the input mailbox,
        // so every start gives the same iris IDs.
        let a = message("a", subject: "Budget", day: 1)
        let b = message("b", day: 2, replyTo: "a", references: ["a"])
        let c = message("c", day: 3, replyTo: "b", references: ["a", "b"])
        let expected = ["work/INBOX/5", "work/[Gmail]/Sent Mail/7", "work/[Gmail]/All Mail/52"]
        let starts = [
            "work/INBOX/5", "work/[Gmail]/Sent Mail/7", "work/[Gmail]/All Mail/50", "work/[Gmail]/All Mail/51",
            "work/[Gmail]/All Mail/52", "work/Projects/3", "work/Projects/4",
        ]
        for rules in SearchRules.allCases {
            let fake = server([
                "INBOX": [5: a],
                "[Gmail]/Sent Mail": [7: b],
                // c was archived: it is only in All Mail and the label.
                "[Gmail]/All Mail": [50: a, 51: b, 52: c],
                "Projects": [3: a, 4: c],
            ], mailboxes: gmailMailboxes, rules: rules)

            for start in starts {
                let found = try await thread(fake, from: start)
                XCTAssertEqual(found, expected, "\(rules) rules, from \(start)")
            }
        }
    }

    func testOnlyTheShownCopiesAreDownloadedInFull() async throws {
        let a = message("a", subject: "Budget", day: 1)
        let b = message("b", day: 2, replyTo: "a", references: ["a"])
        let fake = server([
            "INBOX": [5: a],
            "[Gmail]/Sent Mail": [7: b],
            "[Gmail]/All Mail": [50: a, 51: b],
        ], mailboxes: gmailMailboxes)

        let messages = try await reader(fake).thread(IrisID(account: "work", mailbox: "[Gmail]/All Mail", uid: 51))

        XCTAssertEqual(messages.map(\.rawMessage), [.success(a.raw), .success(b.raw)])
        let calls = await fake.calls
        XCTAssertEqual(calls.filter { if case .fetchRawMessage = $0 { return true } else { return false } }, [
            .fetchRawMessage(5), .fetchRawMessage(7),
        ], "the All Mail copies are read only by their headers")
    }

    func testTwoCopiesInOneMailboxShowTheLowestUID() async throws {
        // Zoho's Sent held two copies of one sent message.
        let expected = ["work/INBOX/69072", "work/Sent/58409", "work/INBOX/69073"]
        let fake = server([
            "INBOX": [
                69072: message("a", subject: "Lunch", day: 1),
                69073: message("c", subject: "Re: Lunch", day: 3, replyTo: "b", references: ["a", "b"]),
            ],
            "Sent": [
                58409: message("b", subject: "Re: Lunch", day: 2, replyTo: "a", references: ["a"]),
                58410: message("b", subject: "Re: Lunch", day: 2, replyTo: "a", references: ["a"]),
            ],
        ])

        for start in ["work/INBOX/69072", "work/Sent/58409", "work/Sent/58410", "work/INBOX/69073"] {
            let found = try await thread(fake, from: start)
            XCTAssertEqual(found, expected, "from \(start)")
        }
    }

    // MARK: - Mailboxes

    func testSearchesINBOXEachSentDraftsAndArchiveWhenThereIsNoAll() async throws {
        let fake = server(["INBOX": [1: message("a", subject: "Budget", day: 1)]])

        _ = try await thread(fake, from: "work/INBOX/1")

        let calls = await fake.calls
        XCTAssertEqual(firstRoundMailboxes(calls), ["INBOX", "Sent", "Sent Messages", "Drafts", "Archive"])
        XCTAssertFalse(calls.contains(.examine("Junk")))
        XCTAssertFalse(calls.contains(.examine("Trash")))
    }

    func testSearchesAllMailButNotSpamTrashOrLabels() async throws {
        let fake = server(["INBOX": [1: message("a", subject: "Budget", day: 1)]], mailboxes: gmailMailboxes)

        _ = try await thread(fake, from: "work/INBOX/1")

        let calls = await fake.calls
        XCTAssertEqual(firstRoundMailboxes(calls), ["INBOX", "[Gmail]/Sent Mail", "[Gmail]/Drafts", "[Gmail]/All Mail"])
        for skipped in ["Projects", "[Gmail]", "[Gmail]/Spam", "[Gmail]/Trash"] {
            XCTAssertFalse(calls.contains(.examine(skipped)), skipped)
        }
    }

    func testSearchesTheInputMailboxFirstWithoutOpeningItAgain() async throws {
        // It is open already, and its answer must have the input message. (Its
        // copies still come last when iris picks a copy to show.)
        let fake = server(["Projects": [3: message("a", subject: "Budget", day: 1)]], mailboxes: gmailMailboxes)

        _ = try await thread(fake, from: "work/Projects/3")

        let calls = await fake.calls
        XCTAssertEqual(
            firstRoundMailboxes(calls),
            ["Projects", "INBOX", "[Gmail]/Sent Mail", "[Gmail]/Drafts", "[Gmail]/All Mail"]
        )
        XCTAssertEqual(Array(calls.prefix(5)), [
            .login, .examine("Projects"), .fetchThreadHeaders([3]), .listMailboxes, .searchSubject(["budget"]),
        ])
    }

    func testSearchesAMailboxWithTwoAttributesOnceInItsFirstPlace() async throws {
        let mailboxes = [
            MailboxInfo(name: "INBOX", attributes: []),
            MailboxInfo(name: "All Mail", attributes: [#"\Archive"#, #"\All"#]),
            MailboxInfo(name: "Sent", attributes: [#"\Sent"#]),
        ]
        let fake = server(["INBOX": [1: message("a", subject: "Budget", day: 1)]], mailboxes: mailboxes)

        _ = try await thread(fake, from: "work/INBOX/1")

        let calls = await fake.calls
        XCTAssertEqual(firstRoundMailboxes(calls), ["INBOX", "Sent", "All Mail"])
    }

    func testMailboxNamesAreDecodedInIrisIDsAndEncodedForEXAMINE() async throws {
        let mailboxes = [
            MailboxInfo(name: "INBOX", attributes: []),
            MailboxInfo(name: "Gesendete Objekte", attributes: [#"\Sent"#]),
            MailboxInfo(name: "Gesch&AOQ-ft", attributes: [#"\Archive"#]),
        ]
        let fake = server([
            "INBOX": [1: message("a", subject: "Budget", day: 1)],
            "Gesch&AOQ-ft": [9: message("b", day: 2, replyTo: "a", references: ["a"])],
        ], mailboxes: mailboxes)

        let found = try await thread(fake, from: "work/INBOX/1")

        XCTAssertEqual(found, ["work/INBOX/1", "work/Geschäft/9"])
        let calls = await fake.calls
        XCTAssertTrue(calls.contains(.examine("Gesch&AOQ-ft")))
        XCTAssertFalse(calls.contains(.examine("Geschäft")))
    }

    // MARK: - Order

    func testOldestFirstByTheDateHeaderElseTheInternalDate() async throws {
        var b = message("b", day: 0, replyTo: "a", references: ["a"])
        b.date = nil
        b.internalDate = day(1)
        let fake = server([
            "INBOX": [
                1: message("a", subject: "Budget", day: 3),
                2: b,
                3: message("c", day: 2, replyTo: "a", references: ["a"]),
            ],
        ])

        let found = try await thread(fake, from: "work/INBOX/1")

        XCTAssertEqual(found, ["work/INBOX/2", "work/INBOX/3", "work/INBOX/1"])
    }

    func testMessagesWithTheSameDateAreInMailboxOrder() async throws {
        let fake = server([
            "INBOX": [9: message("a", subject: "Budget", day: 1)],
            "Sent": [5: message("b", day: 1, replyTo: "a", references: ["a"])],
        ])

        let found = try await thread(fake, from: "work/Sent/5")

        XCTAssertEqual(found, ["work/INBOX/9", "work/Sent/5"])
    }

    // MARK: - No Message-ID

    func testAMessageWithoutAMessageIDIsAThreadOfItsOwn() async throws {
        let fake = server([
            "INBOX": [
                1: message(nil, day: 2, replyTo: "a", references: ["a"]),
                2: message("a", subject: "Budget", day: 1),
            ],
        ])

        let found = try await thread(fake, from: "work/INBOX/1")

        XCTAssertEqual(found, ["work/INBOX/1"])
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchThreadHeaders([1]), .fetchRawMessage(1), .logout])
    }

    // MARK: - Searches

    func testSearchesTheMessageIDsInChunksOfTenIDs() async throws {
        // Zoho gave wrong answers for large OR trees. An empty subject means no SUBJECT search.
        let references = (1...23).map { "r\($0)" }
        let fake = server(["INBOX": [1: message("a", subject: "", day: 1, replyTo: "r23", references: references)]])

        _ = try await thread(fake, from: "work/INBOX/1")

        let calls = await fake.calls
        var searches: [String: [[String]]] = [:]
        var mailbox = ""
        for call in calls {
            switch call {
            case .examine(let name):
                mailbox = name
            case .searchMessageIDs(let values):
                XCTAssertLessThanOrEqual(values.count, MailReader.messageIDSearchChunkSize)
                searches[mailbox, default: []].append(values)
            default:
                break
            }
        }
        // a's own ID and its 23 references: 24 IDs, in one round.
        let allIDs = Set((["a"] + references).map(id))
        XCTAssertEqual(Set(searches.keys), ["INBOX", "Sent", "Sent Messages", "Drafts", "Archive"])
        for (mailbox, chunks) in searches {
            XCTAssertEqual(chunks.map(\.count), [10, 10, 4], mailbox)
            XCTAssertEqual(Set(chunks.joined()), allIDs, mailbox)
        }
    }

    func testNoMessageIDSearchesRunWhereTheSubjectSearchRan() async throws {
        // Every member has the subject, so the SUBJECT search finds them all.
        let fake = server([
            "INBOX": [
                10: message("a", subject: "Budget", day: 1),
                12: message("c", day: 3, replyTo: "b", references: ["b"]),
            ],
            "Sent": [
                20: message("b", day: 2, replyTo: "a", references: ["a"]),
                21: message("d", day: 4, replyTo: "c", references: ["c"]),
            ],
        ])

        let found = try await thread(fake, from: "work/INBOX/10")

        XCTAssertEqual(found, ["work/INBOX/10", "work/Sent/20", "work/INBOX/12", "work/Sent/21"])
        let calls = await fake.calls
        XCTAssertEqual(messageIDSearches(calls), [])
        XCTAssertEqual(subjectSearches(calls), Array(repeating: ["budget"], count: 5))
    }

    func testWithoutTheSubjectSearchTheMessageIDSearchesWalkAChainOneParentAtATime() async throws {
        // A server that refuses "Café", which has no ASCII word, and each reply
        // names only its parent, so each round finds one more parent.
        let fake = server([
            "INBOX": [
                10: message("a", subject: "Café", day: 1),
                12: message("c", subject: "Re: Café", day: 3, replyTo: "b", references: ["b"]),
            ],
            "Sent": [
                20: message("b", subject: "Re: Café", day: 2, replyTo: "a", references: ["a"]),
                21: message("d", subject: "Re: Café", day: 4, replyTo: "c", references: ["c"]),
            ],
        ], refusesNonASCII: true)
        IrisLog.handler = { _ in }
        defer { IrisLog.handler = nil }

        let found = try await thread(fake, from: "work/Sent/21")

        XCTAssertEqual(found, ["work/INBOX/10", "work/Sent/20", "work/INBOX/12", "work/Sent/21"])
        let calls = await fake.calls
        XCTAssertEqual(subjectSearches(calls), [["café"]], "refused once, then never tried again")
        XCTAssertEqual(messageIDSearches(calls), [
            [id("d"), id("c")], [id("d"), id("c")], [id("d"), id("c")], [id("d"), id("c")], [id("d"), id("c")],
            [id("b")], [id("b")], [id("b")], [id("b")], [id("b")],
            [id("a")], [id("a")], [id("a")], [id("a")], [id("a")],
        ])
    }

    func testSearchesTheSubjectWithoutPrefixesOnceInEachMailbox() async throws {
        let fake = server([
            "INBOX": [1: message("a", subject: "Budget", day: 1)],
            "Sent": [2: message("b", subject: "RE: Fwd:  Budget", day: 2, replyTo: "a", references: ["a"])],
        ])

        _ = try await thread(fake, from: "work/Sent/2")

        let calls = await fake.calls
        XCTAssertEqual(subjectSearches(calls), Array(repeating: ["budget"], count: 5))
    }

    func testAMessageWithoutASubjectIsNotSearchedBySubject() async throws {
        // An empty subject would match every message, so only the Message-ID searches run.
        let fake = server([
            "INBOX": [1: message("a", subject: "", day: 1)],
            "Sent": [2: message("b", subject: "Re:", day: 2, replyTo: "a", references: ["a"])],
        ])

        let found = try await thread(fake, from: "work/Sent/2")

        XCTAssertEqual(found, ["work/INBOX/1", "work/Sent/2"])
        let calls = await fake.calls
        XCTAssertEqual(subjectSearches(calls), [])
    }

    func testARefusedSubjectIsSearchedByItsASCIIWordsForTheRestOfTheWalk() async throws {
        // A server that refuses SEARCH text that is not ASCII (Apple smart
        // punctuation puts a curly apostrophe in subjects).
        let expected = ["work/INBOX/1", "work/Sent/2", "work/INBOX/3"]
        for rules in SearchRules.allCases {
            let fake = server([
                "INBOX": [
                    1: message("a", subject: "Adam’s plan for 2026", day: 1),
                    3: message("c", subject: "Re: Adam’s plan for 2026", day: 3, replyTo: "b", references: ["a", "b"]),
                ],
                "Sent": [2: message("b", subject: "Re: Adam’s plan for 2026", day: 2, replyTo: "a", references: ["a"])],
            ], rules: rules, refusesNonASCII: true)
            let recorder = LogRecorder()
            IrisLog.handler = { recorder.record($0) }
            defer { IrisLog.handler = nil }

            let found = try await thread(fake, from: "work/INBOX/1")

            XCTAssertEqual(found, expected, "\(rules) rules")
            let calls = await fake.calls
            XCTAssertEqual(
                subjectSearches(calls),
                [["adam’s plan for 2026"]] + Array(repeating: ["adam", "plan", "2026", "for"], count: 5),
                "\(rules) rules: the whole subject is tried once"
            )
            XCTAssertEqual(messageIDSearches(calls), [], "\(rules) rules")
            XCTAssertEqual(recorder.lines, [], "\(rules) rules")
        }
    }

    func testWithNoSubjectSearchOnlyTheLinkedMessagesAreFoundAndOneLineIsLogged() async throws {
        // "Café" has no ASCII word, so a server that refuses it gets no SUBJECT
        // search. The Message-ID searches find only the messages that a known
        // message names: the newest finds its ancestors, but not a sibling
        // branch, and the first message finds only itself.
        let messages: [String: [UInt32: Message]] = [
            "INBOX": [
                1: message("a", subject: "Café", day: 1),
                3: message("c", subject: "Re: Café", day: 3, replyTo: "b", references: ["a", "b"]),
                4: message("d", subject: "Re: Café", day: 4, replyTo: "a", references: ["a"]),
            ],
            "Sent": [2: message("b", subject: "Re: Café", day: 2, replyTo: "a", references: ["a"])],
        ]
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }

        let fromC = try await thread(server(messages, refusesNonASCII: true), from: "work/INBOX/3")
        let fromA = try await thread(server(messages, refusesNonASCII: true), from: "work/INBOX/1")

        XCTAssertEqual(fromC, ["work/INBOX/1", "work/Sent/2", "work/INBOX/3"], "d, on another branch, is not found")
        XCTAssertEqual(fromA, ["work/INBOX/1"])
        XCTAssertEqual(recorder.lines.count, 2, "one line per walk")
        XCTAssertEqual(
            recorder.lines.first,
            "The server could not search by subject (NO [BADCHARSET (US-ASCII)] Unsupported charset), so iris followed "
                + "only the message IDs that the messages name, and the thread may miss replies."
        )
        let fromAOnAServerThatTakesUTF8 = try await thread(server(messages), from: "work/INBOX/1")
        XCTAssertEqual(fromAOnAServerThatTakesUTF8, ["work/INBOX/1", "work/Sent/2", "work/INBOX/3", "work/INBOX/4"])
    }

    func testWhenTheASCIIWordsAreRefusedTooTheSubjectSearchesStop() async throws {
        let refused = IrisError.searchFailed(account: "work", reason: "NO busy")
        let fake = server([
            "INBOX": [1: message("a", subject: "Budget plan", day: 1)],
            "Sent": [2: message("b", subject: "Re: Budget plan", day: 2, replyTo: "a", references: ["a"])],
        ], errors: [.searchSubject: refused])
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }

        let found = try await thread(fake, from: "work/Sent/2")

        XCTAssertEqual(found, ["work/INBOX/1", "work/Sent/2"])
        let calls = await fake.calls
        XCTAssertEqual(subjectSearches(calls), [["budget plan"], ["budget", "plan"]], "both tried once, in Sent")
        XCTAssertEqual(messageIDSearches(calls).count, 5, "every mailbox is searched by Message-ID instead")
        XCTAssertEqual(recorder.lines.count, 1)
    }

    func testASubjectSearchThatMissesTheMessageItselfIsNotUsed() async throws {
        // An RFC 3501 server matches text inside the subject, so "budget plan"
        // misses a subject with two spaces in it. In the input's own mailbox the
        // answer must have the input, so iris tries the words instead.
        let fake = server([
            "INBOX": [1: message("a", subject: "Budget  plan", day: 1)],
            "Sent": [2: message("b", subject: "Re: Budget  plan", day: 2, replyTo: "a", references: ["a"])],
        ], rules: .rfc3501)

        let found = try await thread(fake, from: "work/Sent/2")

        XCTAssertEqual(found, ["work/INBOX/1", "work/Sent/2"])
        let calls = await fake.calls
        XCTAssertEqual(subjectSearches(calls), [["budget plan"]] + Array(repeating: ["budget", "plan"], count: 5))
    }

    func testASubjectThatTheServerCannotFindFallsBackToTheMessageIDs() async throws {
        // Zoho finds nothing for a word shorter than 3, so the search for "ai"
        // misses the input message, and "ai" has no word to try instead.
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        let fake = server([
            "INBOX": [1: message("a", subject: "AI", day: 1)],
            "Sent": [2: message("b", subject: "Re: AI", day: 2, replyTo: "a", references: ["a"])],
        ])

        let found = try await thread(fake, from: "work/Sent/2")

        XCTAssertEqual(found, ["work/INBOX/1", "work/Sent/2"])
        XCTAssertEqual(recorder.lines, [
            "The server could not search by subject (the search did not find the message itself), so iris followed "
                + "only the message IDs that the messages name, and the thread may miss replies.",
        ])
    }

    // MARK: - Errors

    func testAnUnknownMessageThrowsAndLogsOut() async {
        let fake = server(["INBOX": [1: message("a", subject: "Budget", day: 1)]])
        let missing = IrisID(account: "work", mailbox: "INBOX", uid: 99)

        await assertThrows(.unknownMessage(missing)) { try await self.reader(fake).thread(missing) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchThreadHeaders([99]), .logout])
    }

    func testUIDZeroIsRejectedBeforeConnecting() async {
        let fake = server([:])
        let zero = IrisID(account: "work", mailbox: "INBOX", uid: 0)

        await assertThrows(.unknownMessage(zero)) { try await self.reader(fake).thread(zero) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testAnUnknownMailboxThrowsWithTheTypedName() async {
        let fake = server([:])
        let id = IrisID(account: "work", mailbox: "R&D", uid: 1)

        await assertThrows(.unknownMailbox(account: "work", name: "R&D", reason: "NO no such mailbox")) {
            try await self.reader(fake).thread(id)
        }
    }

    func testAMessageThatDoesNotDownloadIsReturnedAsAFailureAndTheRestStillDownload() async throws {
        let timeout = IrisError.messageDownloadTimedOut(seconds: 10)
        let gone = IrisError.unknownMessage(IrisID(account: "work", mailbox: "INBOX", uid: 3))
        let a = message("a", subject: "Budget", day: 1)
        let c = message("c", day: 3, replyTo: "b", references: ["a", "b"])
        let d = message("d", day: 4, replyTo: "c", references: ["a", "b", "c"])
        let fake = server([
            "INBOX": [1: a, 3: c, 4: d],
            "Sent": [2: message("b", day: 2, replyTo: "a", references: ["a"])],
        ], rawMessageErrors: [2: timeout, 3: gone])

        let messages = try await reader(fake).thread(IrisID(account: "work", mailbox: "INBOX", uid: 4))

        XCTAssertEqual(messages.map(\.irisID.description), ["work/INBOX/1", "work/Sent/2", "work/INBOX/3", "work/INBOX/4"])
        XCTAssertEqual(messages.map(\.rawMessage), [.success(a.raw), .failure(timeout), .failure(gone), .success(d.raw)])
        let calls = await fake.calls
        let downloads = calls.drop { if case .fetchRawMessage = $0 { return false } else { return true } }
        XCTAssertEqual(Array(downloads), [
            // After a failed download the mailbox is opened again: SwiftMail
            // reconnects after a timeout, and a new connection has no mailbox open.
            .fetchRawMessage(1), .fetchRawMessage(3), .examine("INBOX"), .fetchRawMessage(4),
            .examine("Sent"), .fetchRawMessage(2), .logout,
        ])
    }

    func testOtherSubjectSearchErrorsStillFailAndLogOut() async {
        let failure = IrisError.serverTimedOut(account: "work", command: "SEARCH")
        let fake = server(["INBOX": [1: message("a", subject: "Budget", day: 1)]], errors: [.searchSubject: failure])

        await assertThrows(failure) { try await self.thread(fake, from: "work/INBOX/1") }

        let calls = await fake.calls
        XCTAssertEqual(calls.last, .logout)
    }

    func testEachFailingCallLogsOut() async {
        let failure = IrisError.connectionLost(account: "work", command: "FETCH", reason: "reset")
        let methods: [FakeMailClient.Method] = [
            .listMailboxes, .searchSubject, .searchMessageIDs, .fetchThreadHeaders, .fetchRawMessage,
        ]
        for method in methods {
            // The Message-ID searches run only when no SUBJECT search does: for an empty subject.
            let subject = method == .searchMessageIDs ? "" : "Budget"
            let fake = server([
                "INBOX": [1: message("a", subject: subject, day: 1)],
                "Sent": [2: message("b", subject: subject, day: 2, replyTo: "a", references: ["a"])],
            ], errors: [method: failure])

            await assertThrows(failure) { try await self.thread(fake, from: "work/INBOX/1") }

            let calls = await fake.calls
            XCTAssertEqual(calls.last, .logout, "\(method)")
            XCTAssertEqual(calls.filter { $0 == .logout }.count, 1, "\(method)")
        }
    }

    func testTheThreadIsOneSession() async throws {
        let fake = server([
            "INBOX": [1: message("a", subject: "Budget", day: 1)],
            "Sent": [2: message("b", day: 2, replyTo: "a", references: ["a"])],
        ])

        _ = try await thread(fake, from: "work/INBOX/1")

        let calls = await fake.calls
        XCTAssertEqual(calls.first, .login)
        XCTAssertEqual(calls.last, .logout)
        XCTAssertEqual(calls.filter { $0 == .login }.count, 1)
        XCTAssertEqual(calls.filter { $0 == .logout }.count, 1)
    }
}
