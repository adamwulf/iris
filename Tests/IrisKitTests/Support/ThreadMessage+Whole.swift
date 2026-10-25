import Foundation
@testable import IrisKit

/// A thread message downloaded whole, as the tests of small messages build
/// and read it: by its raw bytes.
extension ThreadMessage {
    /// A message that iris downloaded whole, or could not download.
    init(irisID: IrisID, rawMessage: Result<Data, DownloadFailure>, isInput: Bool = false) {
        self.init(irisID: irisID, download: rawMessage.map(DownloadedMessage.whole), isInput: isInput)
    }

    /// The raw bytes of a message that iris downloaded whole, or why it could
    /// not. Only for a message that was not downloaded in parts.
    var rawMessage: Result<Data, DownloadFailure> {
        download.map { message in
            guard case .whole(let data) = message else {
                preconditionFailure("\(irisID) was downloaded in parts; read `download`")
            }
            return data
        }
    }
}
