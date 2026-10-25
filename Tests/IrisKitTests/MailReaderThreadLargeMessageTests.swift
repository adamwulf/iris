import Foundation
import XCTest
@testable import IrisKit

/// `MailReader.thread` with a large message in the thread: the walk's
/// headers give each message's size, and a message above
/// `MailReader.wholeDownloadLimit` is downloaded in parts, as `show` downloads it.
final class MailReaderThreadLargeMessageTests: XCTestCase {
    private typealias Message = FakeMailClient.Message

    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )

    private func reader(_ fake: FakeMailClient) -> MailReader {
        MailReader(account: account, makeClient: { _ in fake })
    }

    private func id(_ uid: UInt32) -> IrisID {
        IrisID(account: account.name, mailbox: "INBOX", uid: uid)
    }

    private func part(_ components: Int...) -> AttachmentID {
        AttachmentID(components: components)
    }

    /// Noon UTC on day `day` of some month.
    private func day(_ day: Int) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400)
    }

    private var first: Message {
        Message(messageID: "<a@example.com>", subject: "Budget", date: day(1))
    }

    /// The reply with the 20 MB plan attached, which only its outline and body part describe.
    private var plan: Message {
        Message(
            messageID: "<b@example.com>",
            inReplyTo: "<a@example.com>",
            references: ["<a@example.com>"],
            subject: "Re: Budget",
            date: day(2),
            outline: MessageOutline(
                size: 20_000_000,
                headers: MessageHeaders(
                    messageID: "<b@example.com>",
                    subject: "Re: Budget",
                    from: [MailAddress(name: "Bob", address: "bob@example.com")],
                    date: day(2),
                    inReplyTo: "<a@example.com>",
                    references: ["<a@example.com>"]
                ),
                parts: [
                    PartOutline(id: part(1), contentType: "text/plain; charset=utf-8", encoding: "7BIT", size: 18),
                    PartOutline(
                        id: part(2), contentType: "application/pdf", disposition: "attachment", encoding: "BASE64",
                        filename: "plan.pdf", size: 27_000_000
                    ),
                ]
            ),
            bodyParts: [part(1): Data("The plan is here.".utf8)]
        )
    }

    private var last: Message {
        Message(messageID: "<c@example.com>", inReplyTo: "<b@example.com>", references: ["<b@example.com>"], subject: "Re: Budget", date: day(3))
    }

    /// INBOX alone, with the three messages of one thread, UIDs 1 to 3.
    private func server(bodyPartErrors: [UInt32: any Error] = [:]) -> FakeMailClient {
        FakeMailClient(
            mailboxes: [MailboxInfo(name: "INBOX", attributes: [])],
            mailboxMessages: ["INBOX": [1: first, 2: plan, 3: last]],
            bodyPartErrors: bodyPartErrors
        )
    }

    /// The calls after the walk: from the first download on.
    private func downloads(_ calls: [FakeMailClient.Call]) -> [FakeMailClient.Call] {
        Array(calls.drop { if case .fetchRawMessage = $0 { return false } else { return true } })
    }

    func testALargeMessageOfAThreadIsDownloadedInPartsAndTheOthersWhole() async throws {
        let fake = server()

        let messages = try await reader(fake).thread(id(3))

        XCTAssertEqual(messages.map(\.irisID), [id(1), id(2), id(3)])
        XCTAssertEqual(messages[1].download, .success(.parts(MessageParts(
            outline: try XCTUnwrap(plan.outline), bodies: [part(1): Data("The plan is here.".utf8)]
        ))))
        let calls = await fake.calls
        XCTAssertEqual(downloads(calls), [
            .fetchRawMessage(1), .fetchOutline(2), .fetchBodyPart(part(1), 2), .fetchRawMessage(3), .logout,
        ], "the walk's headers gave the sizes, so the small messages need no outline")
    }

    func testAThreadShowsTheBodyAndAttachmentIDsOfItsLargeMessage() async throws {
        let messages = try await reader(server()).thread(id(3))

        let markdown = String(decoding: try await MessageFormatter.render(thread: messages, format: .markdown), as: UTF8.self)

        XCTAssertTrue(markdown.contains("**Iris ID:** `work/INBOX/2`"), markdown)
        XCTAssertTrue(markdown.contains("The plan is here.\n\n---\n\n**Attachments:**\n- `2` plan.pdf (application/pdf, about 19.7 MB)\n"), markdown)
        XCTAssertEqual(markdown.components(separatedBy: "* * *").count, 3, "all three messages")
    }

    func testALargeMessageWhoseBodyTimesOutIsLeftOutAndTheMailboxIsOpenedAgain() async throws {
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        let fake = server(bodyPartErrors: [2: IrisError.bodyDownloadTimedOut(seconds: 60)])

        let messages = try await reader(fake).thread(id(3))

        XCTAssertEqual(messages[1].download, .failure(.bodyTimedOut(seconds: 60)))
        let calls = await fake.calls
        XCTAssertEqual(downloads(calls), [
            .fetchRawMessage(1), .fetchOutline(2), .fetchBodyPart(part(1), 2),
            // SwiftMail opened a new connection after the timeout, where no mailbox is open.
            .examine("INBOX"), .fetchRawMessage(3), .logout,
        ])

        let output = try await MessageFormatter.render(thread: messages, format: .json)
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [[String: Any]])
        XCTAssertEqual(array.compactMap { $0["irisID"] as? String }, ["work/INBOX/1", "work/INBOX/3"])
        XCTAssertEqual(recorder.lines, [
            "Left work/INBOX/2 out of the thread: its body did not download in 60 seconds. "
                + "It may be large, or the connection may be slow. Try again on a faster connection.",
        ])
    }

    /// Another client changed a flag during the walk, and its unsolicited
    /// FETCH came before the body part, so SwiftMail kept no bytes.
    func testALargeMessageWithoutBodyBytesIsLeftOutAndTheMailboxIsOpenedAgain() async throws {
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        var empty = plan
        empty.bodyParts = [part(1): Data()]
        let fake = FakeMailClient(
            mailboxes: [MailboxInfo(name: "INBOX", attributes: [])],
            mailboxMessages: ["INBOX": [1: first, 2: empty, 3: last]]
        )

        let messages = try await reader(fake).thread(id(3))

        XCTAssertEqual(messages.map(\.irisID), [id(1), id(2), id(3)])
        XCTAssertEqual(messages[1].download, .failure(.bodyNotReceived))
        XCTAssertEqual(ThreadMessage.DownloadFailure.bodyNotReceived.irisError(for: id(2)), .bodyNotReceived(id(2)))
        let calls = await fake.calls
        XCTAssertEqual(downloads(calls), [
            .fetchRawMessage(1), .fetchOutline(2), .fetchBodyPart(part(1), 2),
            .examine("INBOX"), .fetchRawMessage(3), .logout,
        ], "the rest of the thread downloads, after one EXAMINE, as after any failed download")

        let output = try await MessageFormatter.render(thread: messages, format: .json)
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: output) as? [[String: Any]])
        XCTAssertEqual(array.compactMap { $0["irisID"] as? String }, ["work/INBOX/1", "work/INBOX/3"])
        XCTAssertEqual(recorder.lines, [
            "Left work/INBOX/2 out of the thread: the server sent no bytes for its body. Run the command again.",
        ])
    }

    func testAThreadOfOneLargeMessageWhoseBodyTimesOutFailsAsShowWould() async throws {
        let fake = FakeMailClient(
            mailboxes: [MailboxInfo(name: "INBOX", attributes: [])],
            mailboxMessages: ["INBOX": [2: plan]],
            bodyPartErrors: [2: IrisError.bodyDownloadTimedOut(seconds: 60)]
        )
        let messages = try await reader(fake).thread(id(2))
        XCTAssertEqual(messages.map(\.irisID), [id(2)])
        XCTAssertEqual(messages.map(\.isInput), [true])

        do {
            _ = try await MessageFormatter.render(thread: messages, format: .markdown)
            XCTFail("expected bodyDownloadTimedOut")
        } catch {
            XCTAssertEqual(error as? IrisError, .bodyDownloadTimedOut(seconds: 60))
        }
    }

    func testTheIDsOfAThreadWithALargeMessageNeedNoDownload() async throws {
        let fake = server()

        let ids = try await reader(fake).threadIDs(id(3))

        XCTAssertEqual(ids, [id(1), id(2), id(3)])
        let calls = await fake.calls
        XCTAssertFalse(calls.contains { call in
            switch call {
            case .fetchRawMessage, .fetchOutline, .fetchBodyPart: return true
            default: return false
            }
        }, "\(calls)")
    }
}
