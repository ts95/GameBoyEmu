import Foundation
import Testing
@testable import GameBoyEmu

@Test func theSaveWrittenLastWinsInEitherDirectionAndDeletionsTravel() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appending(path: UUID().uuidString)
    let local = root.appending(path: "local"), cloud = root.appending(path: "cloud")
    try files.createDirectory(at: local, withIntermediateDirectories: true)
    try files.createDirectory(at: cloud, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }

    func write(_ text: String, to folder: URL, age: TimeInterval) throws {
        let url = folder.appending(path: "game.sav")
        try Data(text.utf8).write(to: url)
        try files.setAttributes([.modificationDate: Date.now - age], ofItemAtPath: url.path)
    }
    func contents(of folder: URL) -> String? {
        (try? Data(contentsOf: folder.appending(path: "game.sav"))).map { String(decoding: $0, as: UTF8.self) }
    }

    // A save that only exists here goes up
    try write("first", to: local, age: 100)
    #expect(CloudSaves.sync(["game"], local: local, cloud: cloud).isEmpty)
    #expect(contents(of: cloud) == "first")
    // In step now, so nothing moves
    #expect(CloudSaves.sync(["game"], local: local, cloud: cloud).isEmpty)

    // A newer one from another device comes down
    try write("second", to: cloud, age: 50)
    #expect(CloudSaves.sync(["game"], local: local, cloud: cloud) == ["game"])
    #expect(contents(of: local) == "second")

    // An older one from another device doesn't
    try write("stale", to: cloud, age: 80)
    #expect(CloudSaves.sync(["game"], local: local, cloud: cloud).isEmpty)
    #expect(contents(of: cloud) == "second")

    // A deletion on another device removes the save here, once
    try write("", to: cloud, age: 10)
    #expect(CloudSaves.sync(["game"], local: local, cloud: cloud) == ["game"])
    #expect(contents(of: local) == nil)
    #expect(CloudSaves.sync(["game"], local: local, cloud: cloud).isEmpty)
}
