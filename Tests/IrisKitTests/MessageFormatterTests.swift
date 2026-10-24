import Foundation
import XCTest
@testable import IrisKit

final class MessageFormatterTests: XCTestCase {
    private let chicago = TimeZone(identifier: "America/Chicago")!

    private let document = MessageDocument(
        messageID: "<reply-2@example.com>",
        subject: "Lunch on Tuesday?",
        from: [MessageAddress(name: "André Martin", email: "andre@example.com")],
        to: [MessageAddress(name: "Adam Wulf", email: "adam@example.com"), MessageAddress(name: nil, email: "jane@example.com")],
        cc: [MessageAddress(name: "Team Lead", email: "lead@example.com")],
        replyTo: [MessageAddress(name: nil, email: "lunch@example.com")],
        date: ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z"),
        inReplyTo: "<first@example.com>",
        references: ["<root@example.com>", "<first@example.com>"],
        body: "Can we meet **Tuesday**?\n\n> Quoted line",
        bodySource: .html,
        attachments: [
            MessageAttachment(filename: "résumé.pdf", contentType: "application/pdf", size: 120_000),
            MessageAttachment(filename: nil, contentType: "text/calendar", size: 512),
        ]
    )

    func testMarkdownForAFullDocument() {
        XCTAssertEqual(MessageFormatter.markdown(document, timeZone: chicago), """
        # Lunch on Tuesday?

        **From:** André Martin <andre@example.com>\u{20}\u{20}
        **To:** Adam Wulf <adam@example.com>, jane@example.com\u{20}\u{20}
        **Cc:** Team Lead <lead@example.com>\u{20}\u{20}
        **Date:** 2026-10-24 13:42 CDT

        ---

        Can we meet **Tuesday**?

        > Quoted line

        ---

        **Attachments:**
        - résumé.pdf (application/pdf, 120 KB)
        - (no filename) (text/calendar, 512 bytes)
        """)
    }

    func testMarkdownForAnEmptyDocument() {
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
        XCTAssertEqual(MessageFormatter.dateText(winter, timeZone: chicago), "2026-01-15 03:05 CST")
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

    func testJSONIsDeterministicAndHasNoAttachmentBytes() throws {
        XCTAssertEqual(try MessageFormatter.json(document), """
        {
          "attachments" : [
            {
              "contentType" : "application/pdf",
              "filename" : "résumé.pdf",
              "size" : 120000
            },
            {
              "contentType" : "text/calendar",
              "size" : 512
            }
          ],
          "body" : "Can we meet **Tuesday**?\\n\\n> Quoted line",
          "bodySource" : "html",
          "cc" : [
            {
              "email" : "lead@example.com",
              "name" : "Team Lead"
            }
          ],
          "date" : "2026-10-24T18:42:00Z",
          "from" : [
            {
              "email" : "andre@example.com",
              "name" : "André Martin"
            }
          ],
          "inReplyTo" : "<first@example.com>",
          "messageID" : "<reply-2@example.com>",
          "references" : [
            "<root@example.com>",
            "<first@example.com>"
          ],
          "replyTo" : [
            {
              "email" : "lunch@example.com"
            }
          ],
          "subject" : "Lunch on Tuesday?",
          "to" : [
            {
              "email" : "adam@example.com",
              "name" : "Adam Wulf"
            },
            {
              "email" : "jane@example.com"
            }
          ]
        }
        """)
    }
}
