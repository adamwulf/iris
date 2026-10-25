import Foundation
import XCTest
@testable import IrisKit

/// `MailReader.message`: one FETCH for the size, the header fields, and the
/// parts, then the whole message, or for a large one only its body parts.
final class MailReaderMessageTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )

    private let chicago = TimeZone(identifier: "America/Chicago")!

    private func reader(_ fake: FakeMailClient) -> MailReader {
        MailReader(account: account, makeClient: { _ in fake })
    }

    /// The iris ID of `uid` in `mailbox` of the test account.
    private func id(_ uid: UInt32, in mailbox: String = "INBOX") -> IrisID {
        IrisID(account: account.name, mailbox: mailbox, uid: uid)
    }

    /// The attachment ID of the part with these section numbers.
    private func part(_ components: Int...) -> AttachmentID {
        AttachmentID(components: components)
    }

    private let small = Data("Subject: Hi\r\n\r\nHello\r\n".utf8)

    /// multipart/mixed(multipart/alternative(text/plain, text/html),
    /// application/pdf, image/jpeg) of `size` bytes, as the outline FETCH gives it.
    private func report(size: Int?) -> MessageOutline {
        MessageOutline(
            size: size,
            headers: MessageHeaders(
                messageID: "<m3@example.com>",
                subject: "Q4 report",
                from: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
                to: [MailAddress(name: "Me", address: "me@example.com")],
                date: ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z")
            ),
            parts: [
                PartOutline(id: part(1, 1), contentType: "text/plain; charset=utf-8", encoding: "7BIT", size: 24),
                PartOutline(id: part(1, 2), contentType: "text/html; charset=utf-8", encoding: "QUOTED-PRINTABLE", size: 40),
                PartOutline(
                    id: part(2), contentType: "application/pdf", disposition: "attachment", encoding: "BASE64",
                    filename: "report.pdf", size: 27_000_000
                ),
                PartOutline(
                    id: part(3), contentType: "image/jpeg", disposition: "inline", encoding: "BASE64",
                    filename: "chart.jpg", contentID: "<chart@example.com>", size: 780_000
                ),
            ]
        )
    }

    private let reportBodies = [
        AttachmentID(components: [1, 1]): Data("The report is attached.".utf8),
        AttachmentID(components: [1, 2]): Data("<p>The <b>report</b> is =\r\nattached.</p>".utf8),
    ]

    /// A fake whose `mailbox` (a wire name) holds `outline` at UID 150, with
    /// `bodies` for its body parts and `raw` as its whole source.
    private func server(
        _ outline: MessageOutline,
        bodies: [AttachmentID: Data] = [:],
        raw: Data? = nil,
        mailbox: String = "INBOX",
        bodyPartErrors: [UInt32: any Error] = [:]
    ) -> FakeMailClient {
        FakeMailClient(
            statuses: [mailbox: MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            rawMessages: raw.map { [150: $0] } ?? [:],
            outlines: [150: outline],
            bodyPartErrors: bodyPartErrors,
            parts: [150: bodies]
        )
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

    // MARK: - Whole or in parts

    func testASmallMessageIsDownloadedWholeAfterTheOutline() async throws {
        let fake = server(MessageOutline(size: small.count, headers: MessageHeaders(), parts: []), raw: small)

        let message = try await reader(fake).message(id(150))

        XCTAssertEqual(message, .whole(small))
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchOutline(150), .fetchRawMessage(150), .logout])
    }

    func testAMessageOfExactlyTheLimitIsDownloadedWhole() async throws {
        let fake = server(report(size: MailReader.wholeDownloadLimit), raw: small)

        let message = try await reader(fake).message(id(150))

        XCTAssertEqual(message, .whole(small))
        XCTAssertEqual(MailReader.wholeDownloadLimit, 1_048_576, "1 MiB")
    }

    func testAMessageOfUnknownSizeIsDownloadedWhole() async throws {
        let fake = server(report(size: nil), raw: small)

        let message = try await reader(fake).message(id(150))

        XCTAssertEqual(message, .whole(small), "as before the size was asked for")
    }

    func testAMessageOneByteOverTheLimitIsDownloadedInParts() async throws {
        let outline = report(size: MailReader.wholeDownloadLimit + 1)
        let fake = server(outline, bodies: reportBodies, raw: small)

        let message = try await reader(fake).message(id(150))

        XCTAssertEqual(message, .parts(MessageParts(outline: outline, bodies: reportBodies)))
        let calls = await fake.calls
        XCTAssertEqual(calls, [
            .login, .examine("INBOX"), .fetchOutline(150),
            .fetchBodyPart(part(1, 1), 150), .fetchBodyPart(part(1, 2), 150), .logout,
        ], "only the text and HTML parts, never the whole message or an attachment")
    }

    func testALargeMessageShowsItsBodyAndAttachmentIDsInMarkdownAndJSON() async throws {
        let fake = server(report(size: 20_000_000), bodies: reportBodies)
        let message = try await reader(fake).message(id(150))

        let markdown = try await MessageFormatter.render(
            message: message, irisID: id(150), format: .markdown, timeZone: chicago
        )
        XCTAssertEqual(String(decoding: markdown, as: UTF8.self), """
        # Q4 report

        **From:** Jane Doe <jane@example.com>\u{20}\u{20}
        **To:** Me <me@example.com>\u{20}\u{20}
        **Date:** 2026-10-24 13:42 CDT\u{20}\u{20}
        **Iris ID:** `work/INBOX/150`\u{20}\u{20}
        **Apple Mail:** <message://%3Cm3@example.com%3E>

        ---

        The **report** is attached.

        ---

        **Attachments:**
        - `2` report.pdf (application/pdf, about 19.7 MB)
        - `3` chart.jpg (image/jpeg, about 570 KB, inline)

        """)

        let json = try await MessageFormatter.render(message: message, irisID: id(150), format: .json)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(object["irisID"] as? String, "work/INBOX/150")
        XCTAssertEqual(object["body"] as? String, "The **report** is attached.")
        XCTAssertEqual(object["bodySource"] as? String, "html")
        let attachments = try XCTUnwrap(object["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.compactMap { $0["attachmentID"] as? String }, ["2", "3"])
        XCTAssertEqual(attachments.compactMap { $0["size"] as? Int }, [19_730_769, 570_000])
        XCTAssertEqual(attachments.compactMap { $0["sizeIsEstimate"] as? Bool }, [true, true])
    }

    func testALargeMessageShowsTheTextPartWithBodyText() async throws {
        let fake = server(report(size: 20_000_000), bodies: reportBodies)
        let message = try await reader(fake).message(id(150))

        let json = try await MessageFormatter.render(message: message, irisID: id(150), format: .json, body: .text)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(object["body"] as? String, "The report is attached.")
    }

    func testAWholeMessageRendersAsRenderRawMessageDoes() async throws {
        for format in MessageDocumentFormat.allCases {
            let old: MessageOutputFormat = format == .markdown ? .markdown : .json
            let output = try await MessageFormatter.render(message: .whole(small), irisID: id(150), format: format)
            let expected = try await MessageFormatter.render(rawMessage: small, irisID: id(150), format: old)
            XCTAssertEqual(output, expected, "\(format)")
        }
        XCTAssertEqual(MessageOutputFormat.markdown.documentFormat, .markdown)
        XCTAssertEqual(MessageOutputFormat.json.documentFormat, .json)
        XCTAssertNil(MessageOutputFormat.raw.documentFormat, "the source is always the whole message")
    }

    // MARK: - Errors

    func testAMissingMessageThrowsUnknownMessageFromTheOutlineFetch() async {
        let fake = server(report(size: 20_000_000))

        await assertThrows(.unknownMessage(id(999))) { try await self.reader(fake).message(self.id(999)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchOutline(999), .logout])
    }

    func testUIDZeroIsRejectedBeforeConnecting() async {
        let fake = server(report(size: 20_000_000))

        await assertThrows(.unknownMessage(id(0))) { try await self.reader(fake).message(self.id(0)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    /// Without a BODYSTRUCTURE there is no part to download, so the whole
    /// message is the only way left to show it, and a line says why it can time out.
    func testALargeMessageWithoutABodyStructureIsDownloadedWholeWithALine() async throws {
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        let fake = server(MessageOutline(size: 20_000_000, headers: MessageHeaders(), parts: []), raw: small)

        let message = try await reader(fake).message(id(150))

        XCTAssertEqual(message, .whole(small))
        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchOutline(150), .fetchRawMessage(150), .logout])
        XCTAssertEqual(recorder.lines, [
            "The server did not describe the parts of work/INBOX/150 (its answer had no BODYSTRUCTURE that iris "
                + "can read), so iris downloads the whole message (20.0 MB), which can time out.",
        ])
    }

    func testABodyPartTimeoutPassesThroughAndLogsOut() async {
        let failure = IrisError.bodyDownloadTimedOut(seconds: 60)
        let fake = server(report(size: 20_000_000), bodies: reportBodies, bodyPartErrors: [150: failure])

        await assertThrows(failure) { try await self.reader(fake).message(self.id(150)) }

        let calls = await fake.calls
        XCTAssertEqual(calls.suffix(2), [.fetchBodyPart(part(1, 1), 150), .logout])
    }

    /// SwiftMail keeps the first FETCH answer: an unsolicited FETCH (FLAGS)
    /// before ours, or BODY[1.1] NIL, gives no bytes. That must not show "(no body)".
    func testNoBytesForABodyPartThatIsNotEmptyThrows() async {
        var bodies = reportBodies
        bodies[part(1, 2)] = Data()
        let fake = server(report(size: 20_000_000), bodies: bodies)

        await assertThrows(.bodyNotReceived(id(150))) { try await self.reader(fake).message(self.id(150)) }

        let calls = await fake.calls
        XCTAssertEqual(calls.suffix(2), [.fetchBodyPart(part(1, 2), 150), .logout])
    }

    func testAnEmptyBodyPartIsNoError() async throws {
        let outline = MessageOutline(size: 2_000_000, headers: MessageHeaders(), parts: [
            PartOutline(id: part(1), contentType: "text/plain", encoding: "7BIT", size: 0),
            PartOutline(id: part(2), contentType: "application/zip", encoding: "BASE64", filename: "a.zip", size: 1_999_000),
        ])
        let fake = server(outline)

        let message = try await reader(fake).message(id(150))
        let document = try await MessageFormatter.document(message: message, irisID: id(150), body: .auto)

        XCTAssertEqual(document.body, "")
        XCTAssertEqual(document.attachments.map(\.attachmentID), [part(2)])
    }

    func testMessageExaminesTheModifiedUTF7NameAndKeepsTheDecodedOneInErrors() async throws {
        let fake = server(report(size: 20_000_000), bodies: reportBodies, mailbox: "[Gmail]/Entw&APw-rfe")

        _ = try await reader(fake).message(id(150, in: "[Gmail]/Entwürfe"))
        await assertThrows(.unknownMessage(id(999, in: "[Gmail]/Entwürfe"))) {
            try await self.reader(fake).message(self.id(999, in: "[Gmail]/Entwürfe"))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls[1], .examine("[Gmail]/Entw&APw-rfe"))
    }
}
