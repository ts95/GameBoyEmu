import Foundation
import Testing
@testable import GameBoyEmu

@Test func theFileWrittenLastWinsInEitherDirectionAndDeletionsTravel() {
    let earlier = Date(timeIntervalSinceReferenceDate: 1000), later = earlier + 60

    // A file that only exists on one side goes to the other
    #expect(CloudSync.step(local: earlier, cloud: nil, isDeletedInCloud: false) == .upload)
    #expect(CloudSync.step(local: nil, cloud: earlier, isDeletedInCloud: false) == .download)
    #expect(CloudSync.step(local: nil, cloud: nil, isDeletedInCloud: false) == .nothing)

    // Between two versions, the newer one wins
    #expect(CloudSync.step(local: later, cloud: earlier, isDeletedInCloud: false) == .upload)
    #expect(CloudSync.step(local: earlier, cloud: later, isDeletedInCloud: false) == .download)
    // In step, give or take the rounding of a date on its way to iCloud and back
    #expect(CloudSync.step(local: earlier, cloud: earlier + 0.5, isDeletedInCloud: false) == .nothing)

    // A deletion on another device removes the file here, once
    #expect(CloudSync.step(local: earlier, cloud: later, isDeletedInCloud: true) == .removeLocal)
    #expect(CloudSync.step(local: nil, cloud: later, isDeletedInCloud: true) == .nothing)
    // A file made after it was deleted elsewhere comes back
    #expect(CloudSync.step(local: later, cloud: earlier, isDeletedInCloud: true) == .upload)
}
