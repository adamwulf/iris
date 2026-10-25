import Foundation
import SwiftMail

/// The Content-Transfer-Encoding of a part that iris downloads on its own
/// (RFC 2045, section 6). `BODY[<section>]` gives the part's bytes as the
/// message holds them, still encoded.
enum TransferEncoding {
    /// `data` without its transfer encoding: base64 and quoted-printable are
    /// decoded, in any case. 7bit, 8bit, binary, no encoding, and an encoding
    /// that iris does not know give `data` unchanged, as does base64 that
    /// cannot be decoded.
    static func decoded(_ data: Data, encoding: String?) -> Data {
        // SwiftMail's decoder reads only the encoding of the part it is given.
        data.decoded(for: MessagePart(section: [1], contentType: "application/octet-stream", encoding: encoding))
    }
}
