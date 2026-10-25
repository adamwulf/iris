import Foundation
import XCTest
@testable import IrisKit

final class TransferEncodingTests: XCTestCase {
    func testTransferDecodingUndoesBase64AndQuotedPrintableInAnyCase() {
        XCTAssertEqual(TransferEncoding.decoded(Data("SGVs\r\nbG8=".utf8), encoding: "BASE64"), Data("Hello".utf8))
        XCTAssertEqual(TransferEncoding.decoded(Data("SGVsbG8=".utf8), encoding: "base64"), Data("Hello".utf8))
        XCTAssertEqual(
            TransferEncoding.decoded(Data("a=3Db =\r\nc=C3=A9".utf8), encoding: "Quoted-Printable"),
            Data("a=b cé".utf8)
        )
    }

    func testTransferDecodingKeepsTheBytesOfTheOtherEncodings() {
        let bytes = Data([0x00, 0xFF, 0x3D, 0x0D, 0x0A])
        for encoding in [nil, "7BIT", "8bit", "BINARY", "x-uuencode"] {
            XCTAssertEqual(TransferEncoding.decoded(bytes, encoding: encoding), bytes, "\(encoding ?? "no encoding")")
        }
    }
}
