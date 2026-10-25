import Foundation
@testable import IrisKit

/// A thread message downloaded whole, as the tests of small messages build
/// it: by its raw bytes.
extension ThreadMessage {
    /// A message that iris downloaded whole, or could not download.
    init(irisID: IrisID, rawMessage: Result<Data, DownloadFailure>, isInput: Bool = false) {
        self.init(irisID: irisID, download: rawMessage.map(DownloadedMessage.whole), isInput: isInput)
    }
}
