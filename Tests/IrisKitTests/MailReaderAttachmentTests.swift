import Foundation
import XCTest
@testable import IrisKit

/// `MailReader.attachment`: one part of a message, found in its BODYSTRUCTURE
/// and fetched alone, then decoded from its Content-Transfer-Encoding.
final class MailReaderAttachmentTests: XCTestCase {
    private let account = Account(
        name: "work", host: "imap.example.com", port: 993, username: "me@example.com",
        authentication: .password("secret")
    )

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

    /// A fake whose `mailbox` (a wire name) holds the message UID 150 with these parts.
    private func server(
        structure: [PartStructure],
        parts: [AttachmentID: Data],
        mailbox: String = "INBOX",
        errors: [FakeMailClient.Method: any Error] = [:]
    ) -> FakeMailClient {
        FakeMailClient(
            statuses: [mailbox: MailboxStatus(messageCount: 1, uidValidity: 7, uidNext: 200)],
            structures: [150: structure],
            parts: [150: parts],
            errors: errors
        )
    }

    /// multipart/mixed(text/plain, application/pdf), as SwiftMail gives its BODYSTRUCTURE.
    private var report: [PartStructure] {
        [
            PartStructure(id: part(1), encoding: "7BIT", size: 24),
            PartStructure(id: part(2), encoding: "BASE64", size: 22),
        ]
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

    func testAttachmentFetchesOnlyThatPartAndDecodesBase64() async throws {
        let fake = server(structure: report, parts: [part(2): Data("SGVsbG8g\r\nV29ybGQ=\r\n".utf8)])

        let attachment = try await reader(fake).attachment(part(2), of: id(150))

        XCTAssertEqual(attachment, Data("Hello World".utf8))
        let calls = await fake.calls
        XCTAssertEqual(calls, [
            .login, .examine("INBOX"), .fetchStructure(150), .fetchPart(part(2), 150), .logout,
        ], "EXAMINE, one BODYSTRUCTURE FETCH, and PEEK only, and never the whole message")
    }

    func testAttachmentDecodesQuotedPrintable() async throws {
        let structure = [PartStructure(id: part(2), encoding: "QUOTED-PRINTABLE", size: 24)]
        let fake = server(structure: structure, parts: [part(2): Data("caf=C3=A9 au =\r\nlait\r\n".utf8)])

        let attachment = try await reader(fake).attachment(part(2), of: id(150))

        XCTAssertEqual(attachment, Data("café au lait\r\n".utf8))
    }

    func testAttachmentWithoutATransferEncodingKeepsItsBytes() async throws {
        let bytes = Data([0x00, 0xFF, 0x0D, 0x0A, 0x41])
        for encoding in [nil, "7BIT", "8BIT", "BINARY"] {
            let structure = [PartStructure(id: part(1), encoding: encoding, size: bytes.count)]
            let fake = server(structure: structure, parts: [part(1): bytes])

            let attachment = try await reader(fake).attachment(part(1), of: id(150))

            XCTAssertEqual(attachment, bytes, "\(encoding ?? "no encoding")")
        }
    }

    /// SwiftMail keeps a message/rfc822 part at its own section, then adds the
    /// parts of the message inside it, so the forwarded message downloads whole.
    func testAForwardedMessageDownloadsWholeAsAnEMLFile() async throws {
        let forwarded = Data("From: jane@example.com\r\nSubject: Plans\r\n\r\nThe plans.\r\n".utf8)
        let structure = [
            PartStructure(id: part(1), encoding: "7BIT", size: 12),
            PartStructure(id: part(2), encoding: "7BIT", size: forwarded.count),
            PartStructure(id: part(2, 1), encoding: "7BIT", size: 12),
            PartStructure(id: part(2, 2), encoding: "BASE64", size: 8),
            PartStructure(id: part(3), encoding: "BASE64", size: 8),
        ]
        let fake = server(structure: structure, parts: [part(2): forwarded, part(2, 2): Data("SGVsbG8=".utf8)])

        let message = try await reader(fake).attachment(part(2), of: id(150))
        XCTAssertEqual(message, forwarded)

        let inner = try await reader(fake).attachment(part(2, 2), of: id(150))
        XCTAssertEqual(inner, Data("Hello".utf8), "a part inside the forwarded message downloads too")
    }

    /// SwiftMail keeps the first FETCH answer: an unsolicited FETCH (FLAGS)
    /// before ours, or BODY[2] NIL, gives no bytes. That must not save an empty file.
    func testNoBytesForAPartThatIsNotEmptyThrowsBeforeAnythingIsWritten() async {
        let fake = server(structure: report, parts: [part(2): Data()])

        await assertThrows(.attachmentNotReceived(id(150), part(2))) {
            try await self.reader(fake).attachment(self.part(2), of: self.id(150))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls.suffix(2), [.fetchPart(part(2), 150), .logout])
    }

    func testAnEmptyPartDownloadsAsNoBytes() async throws {
        for size in [0, nil] as [Int?] {
            let fake = server(structure: [PartStructure(id: part(2), encoding: "BASE64", size: size)], parts: [part(2): Data()])

            let attachment = try await reader(fake).attachment(part(2), of: id(150))

            XCTAssertEqual(attachment, Data(), "BODYSTRUCTURE size \(size.map(String.init) ?? "unknown")")
        }
    }

    func testTheBytesNeedNotMatchTheStructureSize() async throws {
        // Servers count line ends differently; only no bytes at all is an error.
        let fake = server(structure: [PartStructure(id: part(2), encoding: "BASE64", size: 99)], parts: [part(2): Data("SGVsbG8=".utf8)])

        let attachment = try await reader(fake).attachment(part(2), of: id(150))

        XCTAssertEqual(attachment, Data("Hello".utf8))
    }

    func testAnAttachmentIDThatTheMessageDoesNotHaveThrowsUnknownAttachmentAndLogsOut() async {
        let fake = server(structure: report, parts: [:])

        for missing in [part(3), part(2, 1), part(1, 1)] {
            await assertThrows(.unknownAttachment(id(150), missing)) {
                try await self.reader(fake).attachment(missing, of: self.id(150))
            }
        }

        let calls = await fake.calls
        XCTAssertFalse(calls.contains { if case .fetchPart = $0 { return true } else { return false } })
        XCTAssertEqual(calls.last, .logout)
    }

    func testAMissingMessageThrowsUnknownMessageFromTheOneStructureFetch() async {
        let fake = server(structure: report, parts: [:])

        await assertThrows(.unknownMessage(id(999))) {
            try await self.reader(fake).attachment(self.part(2), of: self.id(999))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchStructure(999), .logout])
    }

    /// Every message has a part, so an answer without parts is the server's
    /// fault, not a wrong attachment ID.
    func testAnAnswerWithoutABodyStructureIsNotAnUnknownAttachment() async {
        let fake = server(structure: [], parts: [:])

        await assertThrows(.attachmentStructureMissing(id(150))) {
            try await self.reader(fake).attachment(self.part(2), of: self.id(150))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchStructure(150), .logout])
    }

    func testAStructureFetchTimeoutPassesThroughAndLogsOut() async {
        let failure = IrisError.serverTimedOut(account: "work", command: "FETCH")
        let fake = server(structure: report, parts: [:], errors: [.fetchStructure: failure])

        await assertThrows(failure) { try await self.reader(fake).attachment(self.part(2), of: self.id(150)) }

        let calls = await fake.calls
        XCTAssertEqual(calls, [.login, .examine("INBOX"), .fetchStructure(150), .logout])
    }

    func testUIDZeroIsRejectedBeforeConnecting() async {
        let fake = server(structure: report, parts: [:])

        await assertThrows(.unknownMessage(id(0))) {
            try await self.reader(fake).attachment(self.part(2), of: self.id(0))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls, [])
    }

    func testAttachmentExaminesTheModifiedUTF7NameAndKeepsTheDecodedOneInErrors() async throws {
        let fake = server(
            structure: report, parts: [part(2): Data("SGVsbG8=".utf8)], mailbox: "[Gmail]/Entw&APw-rfe"
        )

        let attachment = try await reader(fake).attachment(part(2), of: id(150, in: "[Gmail]/Entwürfe"))
        XCTAssertEqual(attachment, Data("Hello".utf8))
        await assertThrows(.unknownAttachment(id(150, in: "[Gmail]/Entwürfe"), part(9))) {
            try await self.reader(fake).attachment(self.part(9), of: self.id(150, in: "[Gmail]/Entwürfe"))
        }

        let calls = await fake.calls
        XCTAssertEqual(calls[1], .examine("[Gmail]/Entw&APw-rfe"))
    }

    func testATimeoutOfThePartFetchPassesThroughAndLogsOut() async {
        let failure = IrisError.attachmentDownloadTimedOut(seconds: 60)
        let fake = server(structure: report, parts: [:], errors: [.fetchPart: failure])

        await assertThrows(failure) { try await self.reader(fake).attachment(self.part(2), of: self.id(150)) }

        let calls = await fake.calls
        XCTAssertEqual(calls.suffix(2), [.fetchPart(part(2), 150), .logout])
    }
}
