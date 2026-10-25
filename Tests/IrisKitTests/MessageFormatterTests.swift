import Foundation
import XCTest
@testable import IrisKit

final class MessageFormatterTests: XCTestCase {
    private let chicago = TimeZone(identifier: "America/Chicago")!

    private let document = MessageDocument(
        irisID: IrisID(account: "my_gmail", mailbox: "[Gmail]/All Mail", uid: 77),
        messageID: "<reply-2@example.com>",
        subject: "Lunch on Tuesday?",
        from: [MailAddress(name: "André Martin", address: "andre@example.com")],
        to: [MailAddress(name: "Adam Wulf", address: "adam@example.com"), MailAddress(name: nil, address: "jane@example.com")],
        cc: [MailAddress(name: "Team Lead", address: "lead@example.com")],
        replyTo: [MailAddress(name: nil, address: "lunch@example.com")],
        date: ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z"),
        inReplyTo: "<first@example.com>",
        references: ["<root@example.com>", "<first@example.com>"],
        body: "Can we meet **Tuesday**?\n\n> Quoted line",
        bodySource: .html,
        attachments: [
            MessageAttachment(
                attachmentID: AttachmentID(components: [2]),
                filename: "résumé.pdf", contentType: "application/pdf", size: 120_000, inline: false
            ),
            MessageAttachment(
                attachmentID: AttachmentID(components: [3]),
                filename: nil, contentType: "text/calendar", size: 512, inline: false
            ),
            MessageAttachment(
                attachmentID: AttachmentID(components: [4, 2]),
                filename: "photo.jpg", contentType: "image/jpeg", size: 1_200_000, inline: true
            ),
        ]
    )

    func testMarkdownForAFullDocument() {
        XCTAssertEqual(MessageFormatter.markdown(document, timeZone: chicago), """
        # Lunch on Tuesday?

        **From:** André Martin <andre@example.com>\u{20}\u{20}
        **To:** Adam Wulf <adam@example.com>, jane@example.com\u{20}\u{20}
        **Cc:** Team Lead <lead@example.com>\u{20}\u{20}
        **Date:** 2026-10-24 13:42 CDT\u{20}\u{20}
        **Iris ID:** `my_gmail/[Gmail]/All Mail/77`\u{20}\u{20}
        **Apple Mail:** <message://%3Creply-2@example.com%3E>

        ---

        Can we meet **Tuesday**?

        > Quoted line

        ---

        **Attachments:**
        - `2` résumé.pdf (application/pdf, 120 KB)
        - `3` (no filename) (text/calendar, 512 bytes)
        - `4.2` photo.jpg (image/jpeg, 1.2 MB, inline)
        """)
    }

    /// Only a document from `MessageDecoder` alone has no iris ID; `render` always sets it.
    func testMarkdownForAnEmptyDocumentWithoutAnIrisID() {
        let empty = MessageDocument(
            messageID: nil, subject: " ", from: [], to: [], cc: [], replyTo: [], date: nil,
            inReplyTo: nil, references: [], body: "", bodySource: nil, attachments: []
        )

        XCTAssertEqual(MessageFormatter.markdown(empty, timeZone: chicago), """
        # (no subject)

        **From:** (unknown)\u{20}\u{20}
        **To:** (none)\u{20}\u{20}
        **Date:** (unknown)

        ---

        (no body)
        """)
    }

    func testMarkdownSaysWhenTheEndOfTheBodyIsHidden() {
        let trimmed = MessageDocument(
            messageID: nil, subject: "Re: Lunch", from: [], to: [], cc: [], replyTo: [], date: nil,
            inReplyTo: nil, references: [], body: "Sounds good.", bodySource: .text, bodyTrimmed: true,
            attachments: [MessageAttachment(
                attachmentID: AttachmentID(components: [2]), filename: "menu.pdf", contentType: "application/pdf",
                size: 512, inline: false
            )]
        )

        XCTAssertEqual(MessageFormatter.markdown(trimmed, timeZone: chicago), """
        # Re: Lunch

        **From:** (unknown)\u{20}\u{20}
        **To:** (none)\u{20}\u{20}
        **Date:** (unknown)

        ---

        Sounds good.

        (Quoted text or signature hidden: --full shows it.)

        ---

        **Attachments:**
        - `2` menu.pdf (application/pdf, 512 bytes)
        """)
        XCTAssertTrue(try MessageFormatter.json(trimmed).contains(#""bodyTrimmed" : true"#))
    }

    /// A text reply with a quote under it.
    private let reply = Data("""
    Subject: Re: Lunch\r
    Content-Type: text/plain\r
    \r
    Sounds good.\r
    \r
    On Fri, Oct 24, 2026 at 9:41 AM Jane Doe <jane@example.com> wrote:\r
    > Lunch on Tuesday?\r

    """.utf8)

    func testRenderPassesFull() async throws {
        let message = DownloadedMessage.whole(reply)
        let trimmed = String(decoding: try await MessageFormatter.render(message: message, irisID: irisID, format: .markdown), as: UTF8.self)
        XCTAssertFalse(trimmed.contains("Lunch on Tuesday?"))
        XCTAssertTrue(trimmed.contains(MessageFormatter.trimmedNote))

        let full = String(decoding: try await MessageFormatter.render(message: message, irisID: irisID, format: .markdown, full: true), as: UTF8.self)
        XCTAssertTrue(full.contains("> Lunch on Tuesday?"))
        XCTAssertFalse(full.contains(MessageFormatter.trimmedNote))

        let json = String(decoding: try await MessageFormatter.render(message: message, irisID: irisID, format: .json), as: UTF8.self)
        XCTAssertTrue(json.contains(#""body" : "Sounds good.""#))
        XCTAssertTrue(json.contains(#""bodyTrimmed" : true"#))
    }

    func testDateUsesTheGivenTimeZone() throws {
        let winter = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-15T09:05:00Z"))
        XCTAssertEqual(DateText.string(from: winter, timeZone: chicago, showingZone: true), "2026-01-15 03:05 CST")
    }

    func testSizeText() {
        XCTAssertEqual(MessageFormatter.sizeText(0), "0 bytes")
        XCTAssertEqual(MessageFormatter.sizeText(1), "1 byte")
        XCTAssertEqual(MessageFormatter.sizeText(999), "999 bytes")
        XCTAssertEqual(MessageFormatter.sizeText(1000), "1 KB")
        XCTAssertEqual(MessageFormatter.sizeText(999_499), "999 KB")
        XCTAssertEqual(MessageFormatter.sizeText(999_500), "1.0 MB")
        XCTAssertEqual(MessageFormatter.sizeText(1_500_000), "1.5 MB")
        XCTAssertEqual(MessageFormatter.sizeText(2_000_000_000), "2.0 GB")
    }

    /// A message whose bytes are not valid UTF-8 (a Latin-1 "é"), which only its charset decodes.
    private let latin1Message = Data(
        "Subject: Caf\u{E9}\r\nContent-Type: text/plain; charset=ISO-8859-1\r\n\r\nCaf\u{E9}\r\n"
            .unicodeScalars.map { UInt8($0.value) }
    )

    private let irisID = IrisID(account: "work", mailbox: "INBOX", uid: 42)

    // A whole message renders what it always rendered: the goldens here
    // (`testMarkdownForAFullDocument`, `testJSONIsDeterministicAndHasNoAttachmentBytes`)
    // and in MessageDecoderTests pin the output byte for byte.

    func testRenderMarkdownDecodesShowsTheIrisIDAndEndsWithANewline() async throws {
        let output = try await MessageFormatter.render(
            message: .whole(latin1Message), irisID: irisID, format: .markdown, timeZone: chicago
        )
        var document = try await MessageDecoder.decode(latin1Message)
        document.irisID = irisID
        XCTAssertEqual(String(decoding: output, as: UTF8.self), MessageFormatter.markdown(document, timeZone: chicago) + "\n")
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("Café"))
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("**Iris ID:** `work/INBOX/42`"))
    }

    func testRenderJSONDecodesAddsTheIrisIDAndEndsWithANewline() async throws {
        let output = try await MessageFormatter.render(message: .whole(latin1Message), irisID: irisID, format: .json)
        var document = try await MessageDecoder.decode(latin1Message)
        XCTAssertNil(document.irisID, "the decoder reads only the bytes")
        document.irisID = irisID
        XCTAssertEqual(String(decoding: output, as: UTF8.self), try MessageFormatter.json(document) + "\n")
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains(#""irisID" : "work/INBOX/42""#))
    }

    func testDocumentDecodesAndSetsTheIrisID() async throws {
        let document = try await MessageFormatter.document(message: .whole(latin1Message), irisID: irisID, body: .auto)

        var expected = try await MessageDecoder.decode(latin1Message)
        expected.irisID = irisID
        XCTAssertEqual(document, expected)
    }

    /// A message with a PDF attached at section 2.
    private let withAttachment = Data("""
    Subject: Report\r
    Message-ID: <report@example.com>\r
    Content-Type: multipart/mixed; boundary="m"\r
    \r
    --m\r
    Content-Type: text/plain\r
    \r
    The report is attached.\r
    --m\r
    Content-Type: application/pdf; name="report.pdf"\r
    Content-Disposition: attachment; filename="report.pdf"\r
    Content-Transfer-Encoding: base64\r
    \r
    SGVsbG8=\r
    --m--\r

    """.utf8)

    func testRenderShowsTheAttachmentIDInMarkdownAndJSON() async throws {
        let markdown = try await MessageFormatter.render(message: .whole(withAttachment), irisID: irisID, format: .markdown)
        XCTAssertTrue(
            String(decoding: markdown, as: UTF8.self).contains("- `2` report.pdf (application/pdf, 5 bytes)\n"),
            String(decoding: markdown, as: UTF8.self)
        )

        let json = try await MessageFormatter.render(message: .whole(withAttachment), irisID: irisID, format: .json)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let attachments = try XCTUnwrap(object["attachments"] as? [[String: Any]])
        XCTAssertEqual(attachments.compactMap { $0["attachmentID"] as? String }, ["2"])
    }

    func testRenderPassesTheBodyPreference() async throws {
        let alternative = Data("""
        Subject: Both\r
        Content-Type: multipart/alternative; boundary="b"\r
        \r
        --b\r
        Content-Type: text/plain\r
        \r
        plain *text*\r
        --b\r
        Content-Type: text/html\r
        \r
        <p>html <b>text</b></p>\r
        --b--\r

        """.utf8)
        let text = try await MessageFormatter.render(message: .whole(alternative), irisID: irisID, format: .json, body: .text)
        let html = try await MessageFormatter.render(message: .whole(alternative), irisID: irisID, format: .json, body: .html)
        XCTAssertTrue(String(decoding: text, as: UTF8.self).contains(#""body" : "plain *text*""#))
        XCTAssertTrue(String(decoding: html, as: UTF8.self).contains(#""body" : "html **text**""#))
    }

    // MARK: - Threads

    private let thread = [
        ThreadMessage(
            irisID: IrisID(account: "work", mailbox: "INBOX", uid: 7),
            rawMessage: .success(Data("Subject: Budget\r\nMessage-ID: <a@example.com>\r\n\r\nFirst\r\n".utf8))
        ),
        ThreadMessage(
            irisID: IrisID(account: "work", mailbox: "Sent", uid: 3),
            rawMessage: .success(Data("Subject: Re: Budget\r\nMessage-ID: <b@example.com>\r\n\r\nSecond\r\n".utf8))
        ),
    ]

    private func documents(_ messages: [ThreadMessage], body: BodyPreference = .auto) async throws -> [MessageDocument] {
        var documents: [MessageDocument] = []
        for message in messages {
            let downloaded = try message.download.get()
            documents.append(try await MessageFormatter.document(message: downloaded, irisID: message.irisID, body: body))
        }
        return documents
    }

    func testRenderThreadMarkdownShowsEachMessageInOrderBetweenSeparators() async throws {
        let output = try await MessageFormatter.render(thread: thread, format: .markdown, timeZone: chicago)

        let expected = try await documents(thread).map { MessageFormatter.markdown($0, timeZone: chicago) }
        XCTAssertEqual(String(decoding: output, as: UTF8.self), expected.joined(separator: "\n\n* * *\n\n") + "\n")
        let text = String(decoding: output, as: UTF8.self)
        let first = try XCTUnwrap(text.range(of: "**Iris ID:** `work/INBOX/7`"))
        let second = try XCTUnwrap(text.range(of: "**Iris ID:** `work/Sent/3`"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
    }

    func testRenderThreadMarkdownForOneMessageHasNoSeparator() async throws {
        let output = try await MessageFormatter.render(thread: [thread[0]], format: .markdown, timeZone: chicago)

        let expected = try await documents([thread[0]]).map { MessageFormatter.markdown($0, timeZone: chicago) }
        XCTAssertEqual(String(decoding: output, as: UTF8.self), expected[0] + "\n")
    }

    func testRenderThreadJSONIsAnArrayOfTheShowObjectsInOrder() async throws {
        let output = try await MessageFormatter.render(thread: thread, format: .json)

        let expected = try OutputFormatter.json(try await documents(thread), pretty: true) + "\n"
        XCTAssertEqual(String(decoding: output, as: UTF8.self), expected)
        let decoded = try JSONSerialization.jsonObject(with: output) as? [[String: Any]]
        XCTAssertEqual(decoded?.compactMap { $0["irisID"] as? String }, ["work/INBOX/7", "work/Sent/3"])
        XCTAssertEqual(decoded?.compactMap { $0["messageID"] as? String }, ["<a@example.com>", "<b@example.com>"])
    }

    func testRenderThreadJSONLinesIsTheJSONObjectsOneCompactLineEach() async throws {
        let output = try await MessageFormatter.render(thread: thread, format: .jsonl)
        let json = try await MessageFormatter.render(thread: thread, format: .json)

        let text = String(decoding: output, as: UTF8.self)
        let expected = try await documents(thread).map { try OutputFormatter.json($0, pretty: false) + "\n" }.joined()
        XCTAssertEqual(text, expected)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 3, "one line per message, each ending with a newline")
        XCTAssertEqual(lines.last, "")
        for line in lines.dropLast() {
            XCTAssertTrue(line.hasPrefix(#"{"appleMailURL":"#), "sorted keys, no spaces: \(line)")
        }
        let objects = try lines.dropLast().map { line in
            try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? NSDictionary)
        }
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [NSDictionary])
        XCTAssertEqual(objects, array, "the objects of --format json, in the same order")
    }

    func testRenderThreadShowsTheAttachmentIDsInEveryFormat() async throws {
        let messages = [thread[0], ThreadMessage(irisID: irisID, rawMessage: .success(withAttachment))]

        let markdown = String(decoding: try await MessageFormatter.render(thread: messages, format: .markdown), as: UTF8.self)
        XCTAssertTrue(markdown.contains("- `2` report.pdf (application/pdf, 5 bytes)\n"), markdown)

        let json = try await MessageFormatter.render(thread: messages, format: .json)
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        XCTAssertEqual(array.map { ($0["attachments"] as? [[String: Any]])?.compactMap { $0["attachmentID"] as? String } }, [[], ["2"]])

        let jsonl = String(decoding: try await MessageFormatter.render(thread: messages, format: .jsonl), as: UTF8.self)
        let lines = jsonl.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(#""attachments":[{"attachmentID":"2","#), String(lines[1]))
    }

    func testRenderThreadIDsIsOneIrisIDPerLineAsListWritesThem() throws {
        let ids = [IrisID(account: "work", mailbox: "INBOX", uid: 7), IrisID(account: "work", mailbox: "[Gmail]/Sent Mail", uid: 3)]

        let output = String(decoding: MessageFormatter.render(threadIDs: ids), as: UTF8.self)

        XCTAssertEqual(output, "work/INBOX/7\nwork/[Gmail]/Sent Mail/3\n")
        let rows = ids.map { MessageSummary(irisID: $0, from: nil, subject: "", date: nil, unread: false) }
        XCTAssertEqual(output, try OutputFormatter.render(rows, format: .id))
    }

    func testOnlyTheIDFormatOfAThreadNeedsNoDownload() {
        // `iris thread` downloads the messages for every format with a messagesFormat.
        XCTAssertEqual(ThreadOutputFormat.markdown.messagesFormat, .markdown)
        XCTAssertEqual(ThreadOutputFormat.json.messagesFormat, .json)
        XCTAssertEqual(ThreadOutputFormat.jsonl.messagesFormat, .jsonl)
        XCTAssertNil(ThreadOutputFormat.id.messagesFormat)
    }

    func testOnlyTheRawFormatOfShowNeedsTheWholeMessage() {
        // `iris show` downloads a large message in parts for every format with a documentFormat.
        XCTAssertEqual(MessageOutputFormat.markdown.documentFormat, .markdown)
        XCTAssertEqual(MessageOutputFormat.json.documentFormat, .json)
        XCTAssertNil(MessageOutputFormat.raw.documentFormat, "the source is always the whole message")
    }

    func testRenderThreadPassesTheBodyPreference() async throws {
        let alternative = ThreadMessage(irisID: irisID, rawMessage: .success(Data("""
        Subject: Both\r
        Content-Type: multipart/alternative; boundary="b"\r
        \r
        --b\r
        Content-Type: text/plain\r
        \r
        plain *text*\r
        --b\r
        Content-Type: text/html\r
        \r
        <p>html <b>text</b></p>\r
        --b--\r

        """.utf8)))
        let text = try await MessageFormatter.render(thread: [alternative], format: .json, body: .text)
        let html = try await MessageFormatter.render(thread: [alternative], format: .json, body: .html)
        XCTAssertTrue(String(decoding: text, as: UTF8.self).contains(#""body" : "plain *text*""#))
        XCTAssertTrue(String(decoding: html, as: UTF8.self).contains(#""body" : "html **text**""#))
    }

    func testRenderThreadShowsOnlyEachMessagesOwnTextUnlessFull() async throws {
        let messages = [thread[0], ThreadMessage(irisID: irisID, rawMessage: .success(reply))]

        let trimmed = try await MessageFormatter.render(thread: messages, format: .json)
        let objects = try XCTUnwrap(try JSONSerialization.jsonObject(with: trimmed) as? [[String: Any]])
        XCTAssertEqual(objects.compactMap { $0["body"] as? String }, ["First", "Sounds good."])
        XCTAssertEqual(objects.compactMap { $0["bodyTrimmed"] as? Bool }, [false, true])

        let full = try await MessageFormatter.render(thread: messages, format: .json, full: true)
        let fullObjects = try XCTUnwrap(try JSONSerialization.jsonObject(with: full) as? [[String: Any]])
        XCTAssertEqual(fullObjects.compactMap { $0["bodyTrimmed"] as? Bool }, [false, false])
        XCTAssertTrue((fullObjects[1]["body"] as? String)?.hasSuffix("> Lunch on Tuesday?") == true)
    }

    func testRenderThreadLeavesOutAMessageThatCannotBeShownAndSaysWhy() async throws {
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        let timedOut = ThreadMessage(
            irisID: IrisID(account: "work", mailbox: "Sent Mail", uid: 5), rawMessage: .failure(.timedOut(seconds: 10))
        )
        let notAnEmail = ThreadMessage(irisID: IrisID(account: "work", mailbox: "INBOX", uid: 9), rawMessage: .success(Data()))

        for format in ThreadMessagesFormat.allCases {
            let output = try await MessageFormatter.render(
                thread: [thread[0], timedOut, notAnEmail, thread[1]], format: format, timeZone: chicago
            )
            let expected = try await MessageFormatter.render(thread: thread, format: format, timeZone: chicago)
            XCTAssertEqual(output, expected, "\(format): the others are shown as if the two were not there")
        }
        XCTAssertEqual(recorder.lines.count, 2 * ThreadMessagesFormat.allCases.count, "one line per left-out message, in each format")
        XCTAssertEqual(
            recorder.lines[0],
            "Left work/Sent Mail/5 out of the thread: it did not download in 10 seconds. "
                + "It may be large, or the connection may be slow. Try again on a faster connection."
        )
        XCTAssertTrue(recorder.lines[1].hasPrefix("Left work/INBOX/9 out of the thread: it could not be read as an email ("))
        XCTAssertTrue(recorder.lines[1].hasSuffix("Run `iris show 'work/INBOX/9' --format raw` to see its source."))
    }

    func testRenderThreadWithNothingToShowThrowsTheErrorOfTheInputMessage() async {
        // In practice a thread of one large message whose download timed out:
        // the command then fails as `iris show` does.
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        let other = IrisID(account: "work", mailbox: "INBOX", uid: 9)
        let cases: [(messages: [ThreadMessage], error: IrisError, lines: Int)] = [
            ([ThreadMessage(irisID: irisID, rawMessage: .failure(.timedOut(seconds: 10)), isInput: true)],
             .messageDownloadTimedOut(seconds: 10), 0),
            ([ThreadMessage(irisID: other, rawMessage: .success(Data())),
              ThreadMessage(irisID: irisID, rawMessage: .failure(.gone), isInput: true)],
             .unknownMessage(irisID), 1),
        ]
        for (index, test) in cases.enumerated() {
            for format in ThreadMessagesFormat.allCases {
                let before = recorder.lines.count
                do {
                    _ = try await MessageFormatter.render(thread: test.messages, format: format)
                    XCTFail("case \(index), \(format): expected \(test.error)")
                } catch {
                    XCTAssertEqual(error as? IrisError, test.error, "case \(index), \(format)")
                }
                XCTAssertEqual(recorder.lines.count - before, test.lines, "case \(index), \(format): lines for the others")
            }
        }
    }

    func testRenderThreadNamesTheMessageInEachNoteAboutThePartShown() async throws {
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        let htmlOnly = ThreadMessage(
            irisID: IrisID(account: "work", mailbox: "Sent", uid: 3),
            rawMessage: .success(Data("Subject: Hi\r\nContent-Type: text/html\r\n\r\n<p>Hello</p>\r\n".utf8))
        )

        _ = try await MessageFormatter.render(thread: [thread[0], htmlOnly], format: .json, body: .text)

        XCTAssertEqual(recorder.lines, ["work/Sent/3: The message has no text part, so the html part is shown."])
    }

    func testLeftOutLinesNameTheIrisIDTheReasonAndTheNextStep() {
        let id = IrisID(account: "work", mailbox: "Bob's [x]", uid: 7)
        XCTAssertEqual(
            MessageFormatter.leftOutLine(id, because: .timedOut(seconds: 10)),
            "Left work/Bob's [x]/7 out of the thread: it did not download in 10 seconds. "
                + "It may be large, or the connection may be slow. Try again on a faster connection.",
            "`iris show` would hit the same time limit"
        )
        XCTAssertEqual(
            MessageFormatter.leftOutLine(id, because: .gone),
            "Left work/Bob's [x]/7 out of the thread: it is no longer in its mailbox. Run the command again."
        )
        XCTAssertEqual(
            MessageFormatter.showSourceStep(id),
            #"Run `iris show 'work/Bob'\''s [x]/7' --format raw` to see its source."#
        )
    }

    func testAnHTMLBodyThatCannotBeConvertedIsLeftOutWithTheRightNextStep() async throws {
        struct ConversionFailure: Error, CustomStringConvertible {
            let description = "bad tag"
        }
        let recorder = LogRecorder()
        IrisLog.handler = { recorder.record($0) }
        defer { IrisLog.handler = nil }
        let both = ThreadMessage(irisID: IrisID(account: "work", mailbox: "INBOX", uid: 4), rawMessage: .success(Data("""
        Subject: Both\r
        Content-Type: multipart/alternative; boundary="b"\r
        \r
        --b\r
        Content-Type: text/plain\r
        \r
        plain\r
        --b\r
        Content-Type: text/html\r
        \r
        <p>html</p>\r
        --b--\r

        """.utf8)))
        let htmlOnly = ThreadMessage(
            irisID: IrisID(account: "work", mailbox: "INBOX", uid: 5),
            rawMessage: .success(Data("Subject: Hi\r\nContent-Type: text/html\r\n\r\n<p>Hello</p>\r\n".utf8))
        )

        _ = try await MessageFormatter.render(
            thread: [thread[0], both, htmlOnly], format: .json, body: .html, timeZone: chicago,
            parsingHTMLWith: { _ in throw ConversionFailure() }
        )

        XCTAssertEqual(recorder.lines, [
            "work/INBOX/7: The message has no html part, so the text part is shown.",
            // Only --body html gets here with a text part; it is the way to see the message.
            "Left work/INBOX/4 out of the thread: its HTML body could not be converted to Markdown (bad tag). "
                + "Run `iris show 'work/INBOX/4' --body text` to see its text part.",
            "Left work/INBOX/5 out of the thread: its HTML body could not be converted to Markdown (bad tag). "
                + "Run `iris show 'work/INBOX/5' --format raw` to see its source.",
        ])
    }

    func testAnEstimatedSizeIsAboutInMarkdownAndMarkedInJSON() throws {
        let estimated = MessageDocument(
            messageID: nil, subject: "Scans", from: [], to: [], cc: [], replyTo: [], date: nil,
            inReplyTo: nil, references: [], body: "", bodySource: nil, attachments: [
                MessageAttachment(
                    attachmentID: AttachmentID(components: [2]), filename: "scan.pdf", contentType: "application/pdf",
                    size: 19_730_769, sizeIsEstimate: true, inline: false
                ),
                MessageAttachment(
                    attachmentID: AttachmentID(components: [3]), filename: nil, contentType: "message/rfc822",
                    size: 2400, inline: false
                ),
            ]
        )

        XCTAssertTrue(MessageFormatter.markdown(estimated).hasSuffix("""
        **Attachments:**
        - `2` scan.pdf (application/pdf, about 19.7 MB)
        - `3` (no filename) (message/rfc822, 2 KB)
        """), MessageFormatter.markdown(estimated))
        let json = try MessageFormatter.json(estimated)
        XCTAssertTrue(json.contains("""
              "attachments" : [
                {
                  "attachmentID" : "2",
                  "contentType" : "application/pdf",
                  "filename" : "scan.pdf",
                  "inline" : false,
                  "size" : 19730769,
                  "sizeIsEstimate" : true
                },
                {
                  "attachmentID" : "3",
                  "contentType" : "message/rfc822",
                  "inline" : false,
                  "size" : 2400
                }
              ],
            """), json)
    }

    func testJSONIsDeterministicAndHasNoAttachmentBytes() throws {
        XCTAssertEqual(try MessageFormatter.json(document), """
        {
          "appleMailURL" : "message://%3Creply-2@example.com%3E",
          "attachments" : [
            {
              "attachmentID" : "2",
              "contentType" : "application/pdf",
              "filename" : "résumé.pdf",
              "inline" : false,
              "size" : 120000
            },
            {
              "attachmentID" : "3",
              "contentType" : "text/calendar",
              "inline" : false,
              "size" : 512
            },
            {
              "attachmentID" : "4.2",
              "contentType" : "image/jpeg",
              "filename" : "photo.jpg",
              "inline" : true,
              "size" : 1200000
            }
          ],
          "body" : "Can we meet **Tuesday**?\\n\\n> Quoted line",
          "bodySource" : "html",
          "bodyTrimmed" : false,
          "cc" : [
            {
              "address" : "lead@example.com",
              "name" : "Team Lead"
            }
          ],
          "date" : "2026-10-24T18:42:00Z",
          "from" : [
            {
              "address" : "andre@example.com",
              "name" : "André Martin"
            }
          ],
          "inReplyTo" : "<first@example.com>",
          "irisID" : "my_gmail/[Gmail]/All Mail/77",
          "messageID" : "<reply-2@example.com>",
          "references" : [
            "<root@example.com>",
            "<first@example.com>"
          ],
          "replyTo" : [
            {
              "address" : "lunch@example.com"
            }
          ],
          "subject" : "Lunch on Tuesday?",
          "to" : [
            {
              "address" : "adam@example.com",
              "name" : "Adam Wulf"
            },
            {
              "address" : "jane@example.com"
            }
          ]
        }
        """)
    }
}
