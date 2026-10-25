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
            MessageAttachment(filename: "résumé.pdf", contentType: "application/pdf", size: 120_000, inline: false),
            MessageAttachment(filename: nil, contentType: "text/calendar", size: 512, inline: false),
            MessageAttachment(filename: "photo.jpg", contentType: "image/jpeg", size: 1_200_000, inline: true),
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
        - résumé.pdf (application/pdf, 120 KB)
        - (no filename) (text/calendar, 512 bytes)
        - photo.jpg (image/jpeg, 1.2 MB, inline)
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

    /// A message whose bytes are not valid UTF-8 (a Latin-1 "é"), so `raw` must not re-encode it.
    private let latin1Message = Data(
        "Subject: Caf\u{E9}\r\nContent-Type: text/plain; charset=ISO-8859-1\r\n\r\nCaf\u{E9}\r\n"
            .unicodeScalars.map { UInt8($0.value) }
    )

    private let irisID = IrisID(account: "work", mailbox: "INBOX", uid: 42)

    func testRenderRawGivesTheBytesUnchanged() async throws {
        let output = try await MessageFormatter.render(rawMessage: latin1Message, irisID: irisID, format: .raw)
        XCTAssertEqual(output, latin1Message)
    }

    func testRenderMarkdownDecodesShowsTheIrisIDAndEndsWithANewline() async throws {
        let output = try await MessageFormatter.render(
            rawMessage: latin1Message, irisID: irisID, format: .markdown, timeZone: chicago
        )
        var document = try await MessageDecoder.decode(latin1Message)
        document.irisID = irisID
        XCTAssertEqual(String(decoding: output, as: UTF8.self), MessageFormatter.markdown(document, timeZone: chicago) + "\n")
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("Café"))
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("**Iris ID:** `work/INBOX/42`"))
    }

    func testRenderJSONDecodesAddsTheIrisIDAndEndsWithANewline() async throws {
        let output = try await MessageFormatter.render(rawMessage: latin1Message, irisID: irisID, format: .json)
        var document = try await MessageDecoder.decode(latin1Message)
        XCTAssertNil(document.irisID, "the decoder reads only the bytes")
        document.irisID = irisID
        XCTAssertEqual(String(decoding: output, as: UTF8.self), try MessageFormatter.json(document) + "\n")
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains(#""irisID" : "work/INBOX/42""#))
    }

    func testDocumentDecodesAndSetsTheIrisID() async throws {
        let document = try await MessageFormatter.document(rawMessage: latin1Message, irisID: irisID, body: .auto)

        var expected = try await MessageDecoder.decode(latin1Message)
        expected.irisID = irisID
        XCTAssertEqual(document, expected)
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
        let text = try await MessageFormatter.render(rawMessage: alternative, irisID: irisID, format: .json, body: .text)
        let html = try await MessageFormatter.render(rawMessage: alternative, irisID: irisID, format: .json, body: .html)
        XCTAssertTrue(String(decoding: text, as: UTF8.self).contains(#""body" : "plain *text*""#))
        XCTAssertTrue(String(decoding: html, as: UTF8.self).contains(#""body" : "html **text**""#))
    }

    // MARK: - Threads

    private let thread = [
        ThreadMessage(
            irisID: IrisID(account: "work", mailbox: "INBOX", uid: 7),
            rawMessage: Data("Subject: Budget\r\nMessage-ID: <a@example.com>\r\n\r\nFirst\r\n".utf8)
        ),
        ThreadMessage(
            irisID: IrisID(account: "work", mailbox: "Sent", uid: 3),
            rawMessage: Data("Subject: Re: Budget\r\nMessage-ID: <b@example.com>\r\n\r\nSecond\r\n".utf8)
        ),
    ]

    private func documents(_ messages: [ThreadMessage], body: BodyPreference = .auto) async throws -> [MessageDocument] {
        var documents: [MessageDocument] = []
        for message in messages {
            documents.append(try await MessageFormatter.document(rawMessage: message.rawMessage, irisID: message.irisID, body: body))
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

    func testRenderThreadPassesTheBodyPreference() async throws {
        let alternative = ThreadMessage(irisID: irisID, rawMessage: Data("""
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

        """.utf8))
        let text = try await MessageFormatter.render(thread: [alternative], format: .json, body: .text)
        let html = try await MessageFormatter.render(thread: [alternative], format: .json, body: .html)
        XCTAssertTrue(String(decoding: text, as: UTF8.self).contains(#""body" : "plain *text*""#))
        XCTAssertTrue(String(decoding: html, as: UTF8.self).contains(#""body" : "html **text**""#))
    }

    func testJSONIsDeterministicAndHasNoAttachmentBytes() throws {
        XCTAssertEqual(try MessageFormatter.json(document), """
        {
          "appleMailURL" : "message://%3Creply-2@example.com%3E",
          "attachments" : [
            {
              "contentType" : "application/pdf",
              "filename" : "résumé.pdf",
              "inline" : false,
              "size" : 120000
            },
            {
              "contentType" : "text/calendar",
              "inline" : false,
              "size" : 512
            },
            {
              "contentType" : "image/jpeg",
              "filename" : "photo.jpg",
              "inline" : true,
              "size" : 1200000
            }
          ],
          "body" : "Can we meet **Tuesday**?\\n\\n> Quoted line",
          "bodySource" : "html",
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
