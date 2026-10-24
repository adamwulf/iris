import Foundation
import XCTest
@testable import IrisKit

final class ModifiedUTF7Tests: XCTestCase {
    /// Wire form and name pairs. The first is the example in RFC 3501, section 5.1.3.
    private let pairs: [(wire: String, name: String)] = [
        ("~peter/mail/&U,BTFw-/&ZeVnLIqe-", "~peter/mail/台北/日本語"),
        ("R&-D", "R&D"),
        ("[Gmail]/Entw&APw-rfe", "[Gmail]/Entwürfe"),
        ("&-&-", "&&"),
        ("Inbox &2D3c3w-", "Inbox 📟"),
        ("Tab&AAk-here", "Tab\there"),
        ("&AOQA9gD8-", "äöü"),
    ]

    func testEncode() {
        for pair in pairs {
            XCTAssertEqual(ModifiedUTF7.encode(pair.name), pair.wire, pair.name)
        }
    }

    func testDecode() {
        for pair in pairs {
            XCTAssertEqual(ModifiedUTF7.decode(pair.wire), pair.name, pair.wire)
        }
    }

    func testRoundTrips() {
        for name in ["INBOX", "", "R&D & more", "Ordner/Entwürfe/Ä", "日本語", "📬 Mail", "a&b&-c", "-&-"] {
            XCTAssertEqual(ModifiedUTF7.decode(ModifiedUTF7.encode(name)), name, name)
        }
    }

    func testPlainASCIIIsUnchanged() {
        for name in ["INBOX", "[Gmail]/Sent Mail", "Archive.2024", "~user/a-b_c", ""] {
            XCTAssertEqual(ModifiedUTF7.encode(name), name)
            XCTAssertEqual(ModifiedUTF7.decode(name), name)
        }
    }

    func testInvalidInputDecodesToTheTextUnchanged() {
        let invalid = [
            "R&D",                  // a run that is never closed
            "Entwürfe",             // raw non-ASCII, from a server that sends UTF-8
            "&U,BTFw-&ZeVnLIqe-",   // two runs in a row: RFC 3501 wants one
            "&AGE-",                // "a" in base64: printable ASCII must stand for itself
            "&AA-",                 // an odd number of bytes
            "&2D0-",                // a lone high surrogate
            "&A!B-",                // not a base64 character
            "&U/BTFw-",             // `/` instead of `,`
            "&APw=-",               // padding
        ]
        for wire in invalid {
            XCTAssertEqual(ModifiedUTF7.decode(wire), wire, wire)
        }
    }
}
