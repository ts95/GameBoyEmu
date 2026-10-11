//
//  CloudSync.swift
//  GameBoyEmu
//

import CloudKit
import Foundation

/// Keeps the ROMs and save data on this device in step with a copy in the player's iCloud,
/// so that a game can be carried on from another of their devices.
///
/// The files the app plays from stay where they always were, on the device. This only
/// copies between them and iCloud, so the app works the same without iCloud or a network.
/// Between two versions of a file, the one written last wins.
///
/// Every file is one record in the player's private database, named after the file. A
/// file that was deleted keeps its record, marked as deleted. That way the deletion
/// reaches the other devices as well, instead of one of them putting its copy back.
///
/// ponytail: every sync asks for the date of every record, and nothing is pushed to the
/// other devices: they find out the next time they sync. Keep a change token and
/// subscribe to changes if the library grows large or the wait is ever noticed.
enum CloudSync {
    /// What a sync came to.
    struct Outcome: Sendable {
        /// Whether the player is signed in to iCloud, so that there was anything to sync with.
        var isAvailable = false
        /// The ids of the games whose save on this device was replaced or removed.
        var replacedSaves: Set<String> = []
        /// The ids of the games whose save is now the same here and in iCloud.
        var savesInCloud: Set<String> = []
        /// Whether ROMs were added to or removed from this device.
        var didChangeROMs = false
    }

    /// What to do about one file, going by when each copy of it was written.
    enum Step: Equatable {
        case nothing
        case upload
        case download
        /// The file was deleted on another device after this copy was written.
        case removeLocal
    }

    /// - Parameters:
    ///   - local: When the copy on this device was written, if there is one.
    ///   - cloud: When the copy in iCloud was written or deleted, if iCloud knows the file.
    ///   - isDeletedInCloud: Whether iCloud has the file down as deleted.
    static func step(local: Date?, cloud: Date?, isDeletedInCloud: Bool) -> Step {
        // A second's slack: the date doesn't always survive the trip to the digit
        if let cloud, cloud > (local ?? .distantPast) + 1 {
            if !isDeletedInCloud {
                return .download
            }
            return local == nil ? .nothing : .removeLocal
        }
        if let local, local > (cloud ?? .distantPast) + 1 {
            return .upload
        }
        return .nothing
    }

    /// Brings the saves of the given games, and if asked every ROM, in step with iCloud.
    /// Does nothing when the player isn't signed in to iCloud.
    ///
    /// ponytail: waits for iCloud for as long as that takes. Give it a time limit if
    /// starting a game is ever held up by a bad connection.
    @concurrent
    static func sync(saves ids: [String], roms: Bool) async -> Outcome {
        var outcome = Outcome()
        guard (try? await container.accountStatus()) == .available, let entries = try? await entries() else {
            return outcome
        }
        outcome.isAvailable = true

        for id in ids {
            guard let file = File(kind: .save, name: "\(id).sav") else {
                continue
            }
            let result = await sync(file, with: entries[file.recordName])
            if result.isReplaced {
                outcome.replacedSaves.insert(id)
            }
            if result.isInCloud {
                outcome.savesInCloud.insert(id)
            }
        }

        if roms {
            let local = (try? FileManager.default.contentsOfDirectory(at: GameLibrary.romsDirectory, includingPropertiesForKeys: nil)) ?? []
            let names = Set(local.map(\.lastPathComponent)).union(entries.keys.compactMap { File.name(fromRecordName: $0, kind: .rom) })
            for name in names {
                guard let file = File(kind: .rom, name: name) else {
                    continue
                }
                if await sync(file, with: entries[file.recordName]).isReplaced {
                    outcome.didChangeROMs = true
                }
            }
        }
        return outcome
    }

    /// Records in iCloud that a game's save has been deleted on this device.
    @concurrent
    static func forgetSave(of id: String) async {
        await forget(File(kind: .save, name: "\(id).sav"))
    }

    /// Records in iCloud that a ROM has been removed from this device.
    @concurrent
    static func forgetROM(named name: String) async {
        await forget(File(kind: .rom, name: name))
    }

    // MARK: - Files

    /// A file that is synced: where it is on this device, and what its record is called.
    private struct File {
        enum Kind: String {
            case save = "Save"
            case rom = "ROM"

            var prefix: String { rawValue.lowercased() + "-" }
        }

        let kind: Kind
        let url: URL
        let recordName: String

        /// Record names are plain ASCII, which file names needn't be
        private static let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

        /// `nil` if the file's name is too long to name a record after.
        init?(kind: Kind, name: String) {
            guard let encoded = name.addingPercentEncoding(withAllowedCharacters: Self.plain), encoded.count <= 240 else {
                return nil
            }
            self.kind = kind
            self.recordName = kind.prefix + encoded
            self.url = switch kind {
            case .save: GameLibrary.storageDirectory.appending(path: name)
            case .rom: GameLibrary.romsDirectory.appending(path: name)
            }
        }

        /// The name of the file a record is for, if it is a record of the given kind.
        static func name(fromRecordName recordName: String, kind: Kind) -> String? {
            guard recordName.hasPrefix(kind.prefix),
                  let decoded = String(recordName.dropFirst(kind.prefix.count)).removingPercentEncoding else {
                return nil
            }
            // Only ever the last path component: the name must not lead out of the folder
            let name = URL(filePath: decoded).lastPathComponent
            return name.isEmpty || name == "/" ? nil : name
        }
    }

    /// Does what `step` says for one file. Anything that goes wrong leaves the file as it
    /// was, for the next sync to try again.
    private static func sync(_ file: File, with entry: Entry?) async -> (isReplaced: Bool, isInCloud: Bool) {
        let local = modificationDate(of: file.url)
        let files = FileManager.default
        do {
            switch step(local: local, cloud: entry?.modified, isDeletedInCloud: entry?.isDeleted ?? false) {
            case .nothing:
                return (false, local != nil && entry != nil)

            case .upload:
                guard let local else {
                    return (false, false)
                }
                let record = CKRecord(recordType: file.kind.rawValue, recordID: CKRecord.ID(recordName: file.recordName, zoneID: zone))
                record[fileKey] = CKAsset(fileURL: file.url)
                record[modifiedKey] = local
                record[deletedKey] = 0
                try await save(record)
                return (false, true)

            case .download:
                let record = try await database.record(for: CKRecord.ID(recordName: file.recordName, zoneID: zone))
                guard let entry, let downloaded = (record[fileKey] as? CKAsset)?.fileURL else {
                    return (false, false)
                }
                let data = try Data(contentsOf: downloaded)
                try files.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file.url, options: .atomic)
                // Keep the date the file was made, so every device agrees on which is newer
                try files.setAttributes([.modificationDate: entry.modified], ofItemAtPath: file.url.path)
                return (true, true)

            case .removeLocal:
                try files.removeItem(at: file.url)
                return (true, false)
            }
        } catch {
            return (false, false)
        }
    }

    private static func forget(_ file: File?) async {
        guard let file else {
            return
        }
        let record = CKRecord(recordType: file.kind.rawValue, recordID: CKRecord.ID(recordName: file.recordName, zoneID: zone))
        record[fileKey] = nil
        record[modifiedKey] = Date.now
        record[deletedKey] = 1
        // ponytail: if this fails, say for want of a network, the other devices keep their
        // copy and one of them puts the file back
        try? await save(record)
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - iCloud

    private static let container = CKContainer(identifier: "iCloud.no.tonisucic.GameBoyEmu")
    private static var database: CKDatabase { container.privateCloudDatabase }
    /// A zone of the app's own, because only those can be asked for everything in them
    private static let zone = CKRecordZone.ID(zoneName: "Library")

    private static let fileKey = "file"
    private static let modifiedKey = "modified"
    private static let deletedKey = "isDeleted"

    /// What iCloud knows about a file without downloading it.
    private struct Entry {
        let modified: Date
        let isDeleted: Bool
    }

    /// Every record in iCloud, by name.
    private static func entries() async throws -> [String: Entry] {
        var entries: [String: Entry] = [:]
        var token: CKServerChangeToken?
        do {
            while true {
                // Only the dates are asked for, not the files themselves
                let changes = try await database.recordZoneChanges(inZoneWith: zone, since: token, desiredKeys: [modifiedKey, deletedKey])
                for (id, result) in changes.modificationResultsByID {
                    if let record = try? result.get().record, let modified = record[modifiedKey] as? Date {
                        entries[id.recordName] = Entry(modified: modified, isDeleted: (record[deletedKey] as? Int ?? 0) != 0)
                    }
                }
                token = changes.changeToken
                if !changes.moreComing {
                    break
                }
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // The first sync ever: there is nothing in iCloud yet, not even the zone
            _ = try await database.save(CKRecordZone(zoneID: zone))
        }
        return entries
    }

    /// Saves a record over whatever iCloud has under its name.
    private static func save(_ record: CKRecord) async throws {
        let results = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        // A record that couldn't be saved is reported here rather than thrown
        _ = try results.saveResults[record.recordID]?.get()
    }
}
