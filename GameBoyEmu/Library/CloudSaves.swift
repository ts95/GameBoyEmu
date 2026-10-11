//
//  CloudSaves.swift
//  GameBoyEmu
//

import Foundation

/// Keeps the save data on this device in step with a copy in the player's iCloud, so that
/// a game can be carried on from another of their devices.
///
/// The saves the app plays from stay where they always were, on the device. This only
/// copies between them and iCloud, so the app works the same without iCloud or a network.
/// Between two versions of a save, the one written last wins.
///
/// A deleted save is an empty file in iCloud. That way the deletion reaches the other
/// devices as well, instead of one of them putting its copy back.
enum CloudSaves {
    /// How a save on this device stands with its copy in iCloud.
    enum Status: Sendable {
        /// The same save is in iCloud, where the other devices can get it.
        case synced
        /// The save has been handed to iCloud, which hasn't finished sending it.
        case uploading
        /// iCloud doesn't have this version of the save yet.
        case waiting
    }

    /// Whether the player is signed in to iCloud, so that there is anything to sync with.
    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// How the saves of the given games stand with iCloud. Games without a save on this
    /// device are left out, and so is everything when the player isn't signed in.
    @concurrent
    static func status(of ids: [String]) async -> [String: Status] {
        guard let cloud = folder else {
            return [:]
        }
        var statuses: [String: Status] = [:]
        for id in ids {
            guard let localDate = modificationDate(of: .applicationSupportDirectory.appending(path: "\(id).sav")) else {
                continue
            }
            let values = try? cloud.appending(path: "\(id).sav")
                .resourceValues(forKeys: [.contentModificationDateKey, .ubiquitousItemIsUploadedKey])
            if let cloudDate = values?.contentModificationDate, abs(cloudDate.timeIntervalSince(localDate)) <= 1 {
                statuses[id] = values?.ubiquitousItemIsUploaded == true ? .synced : .uploading
            } else {
                statuses[id] = .waiting
            }
        }
        return statuses
    }

    /// Brings the saves of the given games in step with iCloud. Does nothing when the
    /// player isn't signed in to iCloud.
    ///
    /// ponytail: waits for iCloud to download a newer save for as long as that takes.
    /// Give it a time limit if starting a game is ever held up by a bad connection.
    ///
    /// - Returns: The ids of the games whose save on this device was replaced or removed.
    @concurrent
    static func sync(_ ids: [String]) async -> Set<String> {
        guard let cloud = folder else {
            return []
        }
        return sync(ids, local: .applicationSupportDirectory, cloud: cloud)
    }

    /// Records in iCloud that a game's save has been deleted on this device.
    @concurrent
    static func forget(_ id: String) async {
        guard let cloud = folder?.appending(path: "\(id).sav") else {
            return
        }
        write(Data(), to: cloud, modified: .now)
    }

    /// The same as `sync(_:)`, between any two folders.
    static func sync(_ ids: [String], local: URL, cloud: URL) -> Set<String> {
        var replaced = Set<String>()
        for id in ids {
            let local = local.appending(path: "\(id).sav")
            let cloud = cloud.appending(path: "\(id).sav")
            resolveConflicts(at: cloud)

            let localDate = modificationDate(of: local)
            let cloudDate = modificationDate(of: cloud)
            // A second's slack: the date doesn't always survive the trip to the digit
            if let cloudDate, cloudDate > (localDate ?? .distantPast) + 1 {
                guard let save = read(cloud) else {
                    continue
                }
                if !save.isEmpty {
                    if write(save, to: local, modified: cloudDate) {
                        replaced.insert(id)
                    }
                } else if localDate != nil, (try? FileManager.default.removeItem(at: local)) != nil {
                    replaced.insert(id)
                }
            } else if let localDate, localDate > (cloudDate ?? .distantPast) + 1, let save = read(local) {
                write(save, to: cloud, modified: localDate)
            }
        }
        return replaced
    }

    /// The app's folder in iCloud, or `nil` when the player isn't signed in.
    private static var folder: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appending(path: "Documents")
    }

    private static func modificationDate(of url: URL) -> Date? {
        // Known for a file in iCloud even before its contents have been downloaded
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Reads a file, downloading it from iCloud first if need be.
    private static func read(_ url: URL) -> Data? {
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, error: nil) { url in
            data = try? Data(contentsOf: url)
        }
        return data
    }

    /// Writes a file and gives it the date its contents were made, so that every device
    /// agrees on which version is newer.
    @discardableResult
    private static func write(_ data: Data, to url: URL, modified: Date) -> Bool {
        var isWritten = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: nil) { url in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
                isWritten = true
            } catch {
                // ponytail: not reported; the next sync tries again
            }
        }
        return isWritten
    }

    /// When two devices changed a save before hearing of each other, iCloud keeps both
    /// versions. This settles on the one written last.
    private static func resolveConflicts(at url: URL) {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !conflicts.isEmpty else {
            return
        }
        let current = NSFileVersion.currentVersionOfItem(at: url)?.modificationDate ?? .distantPast
        if let newest = conflicts.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }),
           (newest.modificationDate ?? .distantPast) > current {
            _ = try? newest.replaceItem(at: url)
        }
        conflicts.forEach { $0.isResolved = true }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}
