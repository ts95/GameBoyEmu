//
//  WatchSync.swift
//  GameBoyEmu
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// Keeps the games and save data on the watch in step with the phone's.
///
/// The phone is where games come from. The watch tells it which ROMs and saves it has, and
/// the phone answers by sending the ROMs it lacks and the saves that are newer. A save made
/// on the watch is sent the other way. Between two versions of a save, the one written last
/// wins.
///
/// The same class runs on both devices. The system delivers its callbacks on a background
/// queue, and everything here works on files only, so nothing is shared with the UI.
///
/// ponytail: names the player gave to games on the phone aren't carried over; the watch
/// shows each game's own title. Send them along with the ROMs if that is missed.
final class WatchSync: NSObject, WCSessionDelegate, Sendable {
    /// Posted, on the main queue, when a file from the other device has been put in place.
    /// The object is the id of the game it belongs to.
    static let didReceiveFile = Notification.Name("WatchSyncDidReceiveFile")

    private static let romsKey = "roms"
    private static let savesKey = "saves"
    private static let kindKey = "kind"
    private static let nameKey = "name"
    private static let modifiedKey = "modified"

    /// Starts talking to the other device, if there can be one.
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Watch to phone

    #if os(watchOS)
    /// Tells the phone what is on the watch, so that it sends what is missing.
    func requestGames() {
        guard WCSession.default.activationState == .activated else {
            return // Asked again once activation completes
        }
        let saves = Self.romURLs.reduce(into: [String: Date]()) { saves, rom in
            let id = rom.deletingPathExtension().lastPathComponent
            saves[id] = Self.modificationDate(of: Self.saveURL(forGame: id))
        }
        // Only the latest request matters. Sent as user info, which wakes the phone's app
        // to deliver it; an application context would wait until the app next runs.
        WCSession.default.outstandingUserInfoTransfers.forEach { $0.cancel() }
        WCSession.default.transferUserInfo([
            Self.romsKey: Self.romURLs.map(\.lastPathComponent),
            Self.savesKey: saves,
        ])
    }

    /// Sends a game's save data to the phone.
    func sendSave(of game: Game) {
        Self.sendSave(forGame: game.id)
    }
    #endif

    // MARK: - Phone to watch

    #if os(iOS)
    /// The watch has said what it has: send the ROMs it lacks and the saves that are newer.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let namesOnWatch = Set(userInfo[Self.romsKey] as? [String] ?? [])
        let savesOnWatch = userInfo[Self.savesKey] as? [String: Date] ?? [:]
        let alreadyOnTheirWay = Set(session.outstandingFileTransfers.map(\.file.fileURL))

        for rom in Self.romURLs {
            if !namesOnWatch.contains(rom.lastPathComponent), !alreadyOnTheirWay.contains(rom) {
                session.transferFile(rom, metadata: [Self.kindKey: "rom", Self.nameKey: rom.lastPathComponent])
            }

            let id = rom.deletingPathExtension().lastPathComponent
            if let modified = Self.modificationDate(of: Self.saveURL(forGame: id)),
               modified > savesOnWatch[id] ?? .distantPast,
               !alreadyOnTheirWay.contains(Self.saveURL(forGame: id)) {
                Self.sendSave(forGame: id)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate() // The player switched to another watch
    }
    #endif

    // MARK: - Both ways

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        #if os(watchOS)
        requestGames()
        #endif
    }

    /// A file has arrived. It is only there until this method returns, so it is put in
    /// place right here.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        // Only ever the last path component: the name must not lead out of the folder
        guard let name = (metadata[Self.nameKey] as? String).map({ URL(filePath: $0).lastPathComponent }), !name.isEmpty else {
            return
        }
        let id = URL(filePath: name).deletingPathExtension().lastPathComponent

        let destination: URL
        switch metadata[Self.kindKey] as? String {
        case "rom":
            destination = GameLibrary.romsDirectory.appending(path: name)
        case "save":
            destination = Self.saveURL(forGame: id)
            // Whichever was written last wins. Without a date there is no telling.
            guard let modified = metadata[Self.modifiedKey] as? Date,
                  modified > Self.modificationDate(of: destination) ?? .distantPast else {
                return
            }
        default:
            return
        }

        do {
            let files = FileManager.default
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try files.replaceItemAt(destination, withItemAt: file.fileURL)
            if let modified = metadata[Self.modifiedKey] as? Date {
                // Keep the date the save was made, so both devices agree on which is newer
                try files.setAttributes([.modificationDate: modified], ofItemAtPath: destination.path)
            }
        } catch {
            return // ponytail: dropped silently; it is sent again the next time the watch asks
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didReceiveFile, object: id)
        }
    }

    private static func sendSave(forGame id: String) {
        let url = saveURL(forGame: id)
        guard WCSession.default.activationState == .activated, let modified = modificationDate(of: url) else {
            return
        }
        WCSession.default.transferFile(url, metadata: [kindKey: "save", nameKey: url.lastPathComponent, modifiedKey: modified])
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
