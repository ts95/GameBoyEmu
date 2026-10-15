//
//  WatchSync.swift
//  GameBoyEmu
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivitySwift

/// What the watch has: its ROMs by file name, and when each of its saves was made, by game id.
struct WatchInventory: FireAndForgetRequest {
    let roms: [String]
    let saves: [String: Date]
}

/// A game's save data, on its way to the other device.
struct SaveTransfer: FireAndForgetRequest {
    let gameID: String
    /// When the game made this save. Between two versions, the one made last wins.
    let modified: Date
    let data: Data
}

/// Keeps the games and save data on the watch in step with the phone's.
///
/// The phone is where games come from. The watch tells it which ROMs and saves it has, and
/// the phone answers by sending the ROMs it lacks. Saves go both ways: whenever a game saves,
/// on either device, the save is sent to the other one if it is newer than what that one is
/// known to have.
///
/// ROMs go as files. Requests and saves go as user info, which the system keeps until it
/// has been delivered, even across launches, and which wakes the app at the other end.
///
/// ponytail: names the player gave to games on the phone aren't carried over; the watch
/// shows each game's own title. Send them along with the ROMs if that is missed.
@MainActor
final class WatchSync {
    /// The one connection to the other device. There must only be one, because the system
    /// talks to a single delegate.
    static let shared = WatchSync()

    /// Posted, on the main queue, when a file or save from the other device has been put in
    /// place. The object is the id of the game it belongs to.
    nonisolated static let didReceiveFile = Notification.Name("WatchSyncDidReceiveFile")

    private nonisolated static let kindKey = "kind"
    private nonisolated static let nameKey = "name"
    /// When the save the other device has of each game was made, as far as this one knows,
    /// by game id.
    private static let savesOnOtherDeviceKey = "watchSyncSavesOnOtherDevice"

    private let connection = WatchConnection()

    private init() {
        connection.onFileReceived = { file in
            WatchSync.receiveROM(file)
        }
        connection.register(SaveTransfer.self) { save in
            await WatchSync.shared.receive(save)
            return VoidResponse()
        }
        #if os(iOS)
        connection.register(WatchInventory.self) { inventory in
            await WatchSync.shared.watchHas(inventory)
            return VoidResponse()
        }
        #endif

        // A game has saved: on to the other device with it
        NotificationCenter.default.addObserver(forName: Emulator.didWriteSave, object: nil, queue: .main) { _ in
            Task { @MainActor in
                await WatchSync.shared.sendNewSaves()
            }
        }

        Task {
            #if os(watchOS)
            await requestGames()
            #endif
            await sendNewSaves() // Saves made while there was no connection
        }
    }

    /// Sends the other device every save that is newer than the one it is known to have.
    func sendNewSaves() async {
        // A save is noted as sent before it goes, and a send can't fail once the session is
        // active: the system keeps user info until it has been delivered
        guard (try? await connection.waitForActivation()) != nil else {
            return
        }
        #if os(iOS)
        guard connection.isWatchAppInstalled else {
            return
        }
        #endif
        for rom in Self.romURLs {
            let id = rom.deletingPathExtension().lastPathComponent
            let url = Self.saveURL(forGame: id)
            guard let modified = Self.modificationDate(of: url),
                  modified > savesOnOtherDevice[id] ?? .distantPast,
                  let data = try? Data(contentsOf: url) else {
                continue
            }
            noteSaveOnOtherDevice(id: id, modified: modified)
            await connection.send(SaveTransfer(gameID: id, modified: modified, data: data), strategy: .userInfoOnly)
        }
    }

    // MARK: - Watch to phone

    #if os(watchOS)
    /// Tells the phone what is on the watch, so that it sends what is missing.
    func requestGames() async {
        let saves = Self.romURLs.reduce(into: [String: Date]()) { saves, rom in
            let id = rom.deletingPathExtension().lastPathComponent
            saves[id] = Self.modificationDate(of: Self.saveURL(forGame: id))
        }
        await connection.send(WatchInventory(roms: Self.romURLs.map(\.lastPathComponent), saves: saves), strategy: .userInfoOnly)
    }
    #endif

    // MARK: - Phone to watch

    #if os(iOS)
    /// The watch has said what it has: send the ROMs it lacks and the saves that are newer.
    private func watchHas(_ inventory: WatchInventory) async {
        let namesOnWatch = Set(inventory.roms)
        let alreadyOnTheirWay = Set(connection.session.outstandingFileTransfers.map(\.file.fileURL))
        for rom in Self.romURLs where !namesOnWatch.contains(rom.lastPathComponent) && !alreadyOnTheirWay.contains(rom) {
            _ = try? await connection.transferFile(rom, metadata: [Self.kindKey: "rom", Self.nameKey: rom.lastPathComponent])
        }

        // What the watch says it has is better than what was last sent: the app there may
        // have been deleted and installed again
        savesOnOtherDevice = Dictionary(uniqueKeysWithValues: Self.romURLs.map { rom in
            let id = rom.deletingPathExtension().lastPathComponent
            return (id, inventory.saves[id] ?? .distantPast)
        })
        await sendNewSaves()
    }
    #endif

    // MARK: - Both ways

    /// A save has arrived. It replaces the one here if it is newer.
    private func receive(_ save: SaveTransfer) {
        // Only ever a plain name: the id must not lead out of the folder
        let id = URL(filePath: save.gameID).lastPathComponent
        guard !id.isEmpty else {
            return
        }
        // Either way, the other device has this one, and needn't be sent it back
        noteSaveOnOtherDevice(id: id, modified: save.modified)

        let destination = Self.saveURL(forGame: id)
        guard save.modified > Self.modificationDate(of: destination) ?? .distantPast else {
            return
        }
        do {
            try save.data.write(to: destination, options: .atomic)
            // Keep the date the save was made, so both devices agree on which is newer
            try FileManager.default.setAttributes([.modificationDate: save.modified], ofItemAtPath: destination.path)
        } catch {
            return // ponytail: dropped; the next save, or the watch's next request, brings it again
        }
        NotificationCenter.default.post(name: Self.didReceiveFile, object: id)
    }

    /// A ROM has arrived. The file is only there until this returns, so it is put in place
    /// right here.
    private static func receiveROM(_ file: ReceivedFile) {
        guard file.metadata?[kindKey] as? String == "rom",
              // Only ever the last path component: the name must not lead out of the folder
              let name = (file.metadata?[nameKey] as? String).map({ URL(filePath: $0).lastPathComponent }),
              !name.isEmpty else {
            return
        }
        let destination = GameLibrary.romsDirectory.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: GameLibrary.romsDirectory, withIntermediateDirectories: true)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: file.fileURL)
        } catch {
            return // ponytail: dropped; it is sent again the next time the watch asks
        }
        NotificationCenter.default.post(name: didReceiveFile, object: URL(filePath: name).deletingPathExtension().lastPathComponent)
    }

    private var savesOnOtherDevice: [String: Date] {
        get { UserDefaults.standard.dictionary(forKey: Self.savesOnOtherDeviceKey) as? [String: Date] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.savesOnOtherDeviceKey) }
    }

    private func noteSaveOnOtherDevice(id: String, modified: Date) {
        savesOnOtherDevice[id] = max(savesOnOtherDevice[id] ?? .distantPast, modified)
    }

    /// Every ROM on this device: the ones the player opened and the ones that ship with the app.
    private static var romURLs: [URL] {
        let opened = (try? FileManager.default.contentsOfDirectory(at: GameLibrary.romsDirectory, includingPropertiesForKeys: nil)) ?? []
        let included = GameLibrary.includedROMNames.compactMap { Bundle.main.url(forResource: $0, withExtension: "gb") }
        return opened + included
    }

    private static func saveURL(forGame id: String) -> URL {
        GameLibrary.storageDirectory.appending(path: "\(id).sav")
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
#endif
