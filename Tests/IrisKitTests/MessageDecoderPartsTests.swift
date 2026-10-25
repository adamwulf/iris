import Foundation
import SwiftMail
import XCTest
@testable import IrisKit

/// `MessageDecoder` on a large message that iris downloaded in parts: the
/// header fields and parts from one FETCH, and the bytes of the body parts.
final class MessageDecoderPartsTests: XCTestCase {
    /// Raw message bytes from text with `\n` line ends, sent as CRLF the way a server sends them.
    private func eml(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    /// The attachment ID of the part with these section numbers.
    private func id(_ components: Int...) -> AttachmentID {
        AttachmentID(components: components)
    }

    private let html = "<p>The <b>Q4</b> report is attached.</p>"

    /// multipart/mixed(multipart/alternative(text/plain, text/html),
    /// application/pdf, message/rfc822, image/png), whole.
    private var whole: Data {
        eml("""
        Message-ID: <m3@example.com>
        In-Reply-To: <m2@example.com>
        References: <m1@example.com> <m2@example.com>
        From: Jane Doe <jane@example.com>
        To: Me <me@example.com>, bob@example.com
        Cc: Ann <ann@example.com>
        Reply-To: reports@example.com
        Date: Sat, 24 Oct 2026 13:42:00 -0500
        Subject: Q4 report
        Content-Type: multipart/mixed; boundary="mixed"

        --mixed
        Content-Type: multipart/alternative; boundary="alt"

        --alt
        Content-Type: text/plain; charset=utf-8

        The *Q4* report is attached.
        --alt
        Content-Type: text/html; charset=utf-8

        \(html)
        --alt--
        --mixed
        Content-Type: application/pdf; name="report.pdf"
        Content-Disposition: attachment; filename="report.pdf"
        Content-Transfer-Encoding: base64

        SGVsbG8gV29ybGQ=
        --mixed
        Content-Type: message/rfc822

        Subject: Lunch

        Lunch?
        --mixed
        Content-Type: image/png
        Content-Disposition: inline; filename="logo.png"
        Content-ID: <logo@example.com>
        Content-Transfer-Encoding: base64

        iVBORw0KGgo=
        --mixed--
        """)
    }

    /// The same message as the outline FETCH gives it: the header fields, and
    /// the parts as SwiftMail's BODYSTRUCTURE conversion lists them, also the
    /// part inside the forwarded message (3.1), with SwiftMail's filename for it.
    private var outline: MessageOutline {
        MessageOutline(
            size: 20_000_000,
            headers: MessageHeaders(
                messageID: "<m3@example.com>",
                subject: "Q4 report",
                from: [MailAddress(name: "Jane Doe", address: "jane@example.com")],
                to: [MailAddress(name: "Me", address: "me@example.com"), MailAddress(name: nil, address: "bob@example.com")],
                cc: [MailAddress(name: "Ann", address: "ann@example.com")],
                replyTo: [MailAddress(name: nil, address: "reports@example.com")],
                date: ISO8601DateFormatter().date(from: "2026-10-24T18:42:00Z"),
                inReplyTo: "<m2@example.com>",
                references: ["<m1@example.com>", "<m2@example.com>"]
            ),
            parts: [
                PartOutline(id: id(1, 1), contentType: "text/plain; charset=utf-8", encoding: "7BIT", size: 30),
                PartOutline(id: id(1, 2), contentType: "text/html; charset=utf-8", encoding: "7BIT", size: 41),
                PartOutline(
                    id: id(2), contentType: "application/pdf", disposition: "ATTACHMENT", encoding: "BASE64",
                    filename: "report.pdf", size: 18
                ),
                PartOutline(id: id(3), contentType: "message/rfc822", encoding: "7BIT", filename: "Lunch.eml", size: 26),
                PartOutline(id: id(3, 1), contentType: "text/plain", encoding: "7BIT", size: 8),
                PartOutline(
                    id: id(4), contentType: "image/png", disposition: "INLINE", encoding: "BASE64",
                    filename: "logo.png", contentID: "<logo@example.com>", size: 14
                ),
            ]
        )
    }

    private var bodies: [AttachmentID: Data] {
        [id(1, 1): Data("The *Q4* report is attached.".utf8), id(1, 2): Data(html.utf8)]
    }

    func testTheBodyPartsAreTheTextAndHTMLPartsOutsideTheForwardedMessage() {
        XCTAssertEqual(MessageDecoder.bodyParts(of: outline.parts).map(\.id), [id(1, 1), id(1, 2)])
    }

    func testABodyPartsMessageHasTheBodyHeadersAndAttachmentIDsOfTheWholeMessage() async throws {
        for preference in BodyPreference.allCases {
            let fromWhole = try await MessageDecoder.decode(whole, body: preference)
            let fromParts = try await MessageDecoder.decode(
                MessageParts(outline: outline, bodies: bodies), body: preference,
                convertingHTMLWith: MessageDecoder.markdown(fromHTML:)
            )

            XCTAssertEqual(fromParts.body, fromWhole.body, "\(preference)")
            XCTAssertEqual(fromParts.bodySource, fromWhole.bodySource, "\(preference)")
            for keyPath in [\MessageDocument.from, \.to, \.cc, \.replyTo] {
                XCTAssertEqual(fromParts[keyPath: keyPath], fromWhole[keyPath: keyPath], "\(preference)")
            }
            XCTAssertEqual(fromParts.messageID, fromWhole.messageID)
            XCTAssertEqual(fromParts.appleMailURL, fromWhole.appleMailURL)
            XCTAssertEqual(fromParts.subject, fromWhole.subject)
            XCTAssertEqual(fromParts.date, fromWhole.date)
            XCTAssertEqual(fromParts.inReplyTo, fromWhole.inReplyTo)
            XCTAssertEqual(fromParts.references, fromWhole.references)
            XCTAssertEqual(fromParts.attachments.map(\.attachmentID), [id(2), id(3), id(4)])
            XCTAssertEqual(fromParts.attachments.map(\.attachmentID), fromWhole.attachments.map(\.attachmentID))
            XCTAssertEqual(fromParts.attachments.map(\.contentType), fromWhole.attachments.map(\.contentType))
            XCTAssertEqual(fromParts.attachments.map(\.inline), fromWhole.attachments.map(\.inline))
        }
    }

    func testTheAttachmentsOfABodyPartsMessageHaveTheSizesFromBodyStructure() async throws {
        let document = try await MessageDecoder.decode(
            MessageParts(outline: outline, bodies: bodies), body: .auto, convertingHTMLWith: MessageDecoder.markdown(fromHTML:)
        )

        XCTAssertEqual(document.attachments, [
            // base64: 57 bytes in each 78 of the part.
            MessageAttachment(
                attachmentID: id(2), filename: "report.pdf", contentType: "application/pdf", size: 13,
                sizeIsEstimate: true, inline: false
            ),
            // 7bit: the size of the part is its size. The filename is the one SwiftMail made from the subject.
            MessageAttachment(attachmentID: id(3), filename: "Lunch.eml", contentType: "message/rfc822", size: 26, inline: false),
            MessageAttachment(
                attachmentID: id(4), filename: "logo.png", contentType: "image/png", size: 10, sizeIsEstimate: true, inline: true
            ),
        ])
    }

    /// The whole message gives each size exactly, from its bytes.
    func testTheAttachmentsOfAWholeMessageHaveExactSizes() async throws {
        let document = try await MessageDecoder.decode(whole)

        XCTAssertEqual(document.attachments.map(\.size), [11, 24, 8])
        XCTAssertEqual(document.attachments.map(\.sizeIsEstimate), [false, false, false])
    }

    func testTheDecodedSizeOfAPartWithoutBytes() {
        func size(_ encoding: String?, _ size: Int?) -> (Int, Bool) {
            let result = MessageDecoder.decodedSize(
                of: MessagePart(section: [2], contentType: "application/pdf", encoding: encoding, size: size)
            )
            return (result.bytes, result.isEstimate)
        }
        // 27 MB of base64 in lines of 76 is about 19.7 MB of data.
        XCTAssertTrue(size("BASE64", 27_000_000) == (19_730_769, true))
        XCTAssertTrue(size("base64", 78) == (57, true))
        XCTAssertTrue(size("QUOTED-PRINTABLE", 1000) == (1000, true), "at most its size")
        XCTAssertTrue(size("x-uuencode", 1000) == (1000, true), "an encoding iris does not know")
        for encoding in [nil, "7BIT", "8bit", "BINARY"] {
            XCTAssertTrue(size(encoding, 1000) == (1000, false), "\(encoding ?? "no encoding") is exact")
        }
        XCTAssertTrue(size("BASE64", nil) == (0, true), "no size")
    }

    func testThePartsOfAForwardedMessageAreNotOpenedAsInAWholeMessage() {
        let message = MessageDecoder.message(of: outline.parts, bodies: bodies)

        XCTAssertEqual(message.parts.map(\.section.description), ["1.1", "1.2", "2", "3", "4"])
        XCTAssertEqual(message.parts.compactMap(\.data).count, 2, "only the body parts have bytes")
    }

    func testAPartNamedLikeAForwardedMessageIsNotInsideIt() {
        // 3 is message/rfc822; 30 and 3 itself are not inside it.
        let parts = [
            PartOutline(id: id(3), contentType: "message/rfc822"),
            PartOutline(id: id(3, 1), contentType: "text/plain"),
            PartOutline(id: id(30), contentType: "image/png"),
        ]

        XCTAssertEqual(MessageDecoder.message(of: parts, bodies: [:]).parts.map(\.section.description), ["3", "30"])
    }

    func testABodyPartsMessageDecodesTheTransferEncodingAndCharsetOfItsBody() async throws {
        let latin1 = MessageOutline(size: 2_000_000, headers: MessageHeaders(subject: "Café"), parts: [
            PartOutline(id: id(1), contentType: "text/plain; charset=ISO-8859-1", encoding: "QUOTED-PRINTABLE", size: 40),
            PartOutline(id: id(2), contentType: "application/zip", encoding: "BASE64", filename: "photos.zip", size: 1_999_000),
        ])

        let document = try await MessageDecoder.decode(
            MessageParts(outline: latin1, bodies: [id(1): Data("Caf=E9 au =\r\nlait".utf8)]), body: .auto,
            convertingHTMLWith: MessageDecoder.markdown(fromHTML:)
        )

        XCTAssertEqual(document.body, "Café au lait")
        XCTAssertEqual(document.bodySource, .text)
        XCTAssertEqual(document.attachments.map(\.filename), ["photos.zip"])
    }

    func testAPlainTextAttachmentOfABodyPartsMessageIsNotItsBody() {
        let parts = [
            PartOutline(id: id(1), contentType: "text/plain; charset=utf-8", encoding: "7BIT", size: 5),
            PartOutline(id: id(2), contentType: "text/plain", disposition: "attachment", encoding: "7BIT", filename: "log.txt", size: 9_000_000),
            PartOutline(id: id(3), contentType: "text/calendar", encoding: "7BIT", filename: "invite.ics", size: 900),
        ]

        XCTAssertEqual(MessageDecoder.bodyParts(of: parts).map(\.id), [id(1)], "only the bytes of the body are downloaded")
    }
}
