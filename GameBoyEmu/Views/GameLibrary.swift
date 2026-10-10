//
//  GameLibrary.swift
//  GameBoyEmu
//

import Foundation
import Observation

/// A game the player can start: a ROM file, plus what is known about its use so far.
struct Game: Identifiable, Hashable, Sendable {
    /// What is known about a game's save file.
    struct SaveData: Hashable, Sendable {
        let size: Int
        let modified: Date
    }

    /// The ROM's file name without its extension. Also names the save file.
    let id: String
    /// The title from the cartridge header, or the file name if the header has none.
    let title: String
    let romURL: URL
    /// Whether the ROM ships inside the app, as opposed to having been opened by the player.
    let isIncluded: Bool
    var lastPlayed: Date?
    var save: SaveData?

    /// Saves live in the app's own container, as <rom>.sav
    var saveURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(id).sav")
    }
}

/// The games the app knows about: the ones it ships with and the ones the player has opened.
///
/// A ROM the player opens is copied into the app's own container. That way it can be started
/// again later without asking for access to wherever the original file lives, and it keeps
/// working if the original is moved or deleted.
@MainActor
@Observable
final class GameLibrary {
    /// The games that ship with the app.
    private(set) var included: [Game] = []
    /// The games the player has opened, most recently played first.
    private(set) var recent: [Game] = []

    /// Bundled ROMs to offer, by file name. ROMs that aren't in the bundle are left out.
    private static let includedROMNames = ["pokemon_red"]
    private static let romsDirectory = URL.applicationSupportDirectory.appending(path: "ROMs")
    private static let lastPlayedKey = "lastPlayed"

    private var lastPlayed: [String: Date] {
        get { UserDefaults.standard.dictionary(forKey: Self.lastPlayedKey) as? [String: Date] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastPlayedKey) }
    }

    /// Reads the library from disk again, picking up new save data and play dates.
    func reload() {
        included = Self.includedROMNames
            .compactMap { Bundle.main.url(forResource: $0, withExtension: "gb") }
            .map { game(at: $0, isIncluded: true) }

        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.romsDirectory, includingPropertiesForKeys: nil)) ?? []
        recent = urls
            .map { game(at: $0, isIncluded: false) }
            .sorted { ($0.lastPlayed ?? .distantPast, $1.title) > ($1.lastPlayed ?? .distantPast, $0.title) }
    }

    /// Adds a ROM the player picked to the library.
    ///
    /// - Parameter url: The picked file, as handed out by the system's file picker.
    /// - Returns: The game, ready to be started.
    /// - Throws: `GameBoyError` if the file isn't a game this emulator can run, or can't be copied.
    func importROM(from url: URL) throws -> Game {
        // A file from the picker lives outside the app's sandbox, and may only be read
        // between these two calls
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let name = url.deletingPathExtension().lastPathComponent
        let rom: Data
        do {
            rom = try Data(contentsOf: url)
        } catch {
            throw GameBoyError.romNotReadable(name: name, reason: error.localizedDescription)
        }

        // Refuse files that would only fail later, before they end up in the library
        try GameBoyMemory().loadCartridge(data: rom)

        let destination = Self.romsDirectory.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: Self.romsDirectory, withIntermediateDirectories: true)
            try rom.write(to: destination, options: .atomic)
        } catch {
            throw GameBoyError.romNotAdded(name: name, reason: error.localizedDescription)
        }

        reload()
        return game(at: destination, isIncluded: false)
    }

    /// Records that a game is being started now.
    func markPlayed(_ game: Game) {
        lastPlayed[game.id] = .now
    }

    /// Removes a game the player opened from the library. Its save data is kept.
    func remove(_ game: Game) throws {
        guard !game.isIncluded else {
            return
        }
        do {
            try FileManager.default.removeItem(at: game.romURL)
        } catch {
            throw GameBoyError.unexpected(reason: error.localizedDescription)
        }
        lastPlayed[game.id] = nil
        reload()
    }

    /// Deletes a game's save data. This can't be undone.
    func deleteSave(of game: Game) throws {
        do {
            try FileManager.default.removeItem(at: game.saveURL)
        } catch {
            throw GameBoyError.unexpected(reason: error.localizedDescription)
        }
        reload()
    }

    private func game(at url: URL, isIncluded: Bool) -> Game {
        let id = url.deletingPathExtension().lastPathComponent
        var game = Game(id: id, title: Self.title(ofROMAt: url) ?? id, romURL: url, isIncluded: isIncluded)
        game.lastPlayed = lastPlayed[id]

        if let attributes = try? FileManager.default.attributesOfItem(atPath: game.saveURL.path),
           let size = attributes[.size] as? Int,
           let modified = attributes[.modificationDate] as? Date {
            game.save = Game.SaveData(size: size, modified: modified)
        }
        return game
    }

    /// Reads the game's title from the cartridge header (0x0134-0x0143).
    private static func title(ofROMAt url: URL) -> String? {
        guard let rom = try? Data(contentsOf: url, options: .mappedIfSafe), rom.count >= 0x150 else {
            return nil
        }
        // The title is padded with zeros, and on newer cartridges its last bytes hold other
        // things, so it ends at the first byte that isn't a printable character
        let bytes = rom[(rom.startIndex + 0x134)..<(rom.startIndex + 0x144)].prefix { (0x20...0x7E).contains($0) }
        let title = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title.capitalized
    }
}
