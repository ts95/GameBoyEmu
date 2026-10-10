//
//  GameBoyError.swift
//  GameBoyEmu
//

import Foundation

/// Everything that can go wrong while loading or running a game.
///
/// The descriptions are written for the player: `errorDescription` says what happened and
/// `recoverySuggestion` says what, if anything, can be done about it. Underlying system errors
/// are carried as text so the error can be passed between the emulator and the UI.
enum GameBoyError: LocalizedError, Equatable, Sendable {
    /// The app bundle has no ROM with this name.
    case romNotFound(name: String)
    /// The ROM file exists but couldn't be read.
    case romNotReadable(name: String, reason: String)
    /// The data is too small to be a Game Boy ROM.
    case invalidROM
    /// The cartridge has a bank controller chip this emulator doesn't implement.
    case unsupportedCartridge(type: UInt8)
    /// The game executed an opcode that doesn't exist.
    case invalidInstruction(opcode: UInt8, address: UInt16)
    /// A save file exists but couldn't be read.
    case saveNotReadable(reason: String)
    /// The save file couldn't be written. The game keeps running.
    case saveNotWritten(reason: String)
    /// Sound couldn't be started. The game keeps running, silently.
    case audioUnavailable(reason: String)
    /// Anything that isn't one of the above.
    case unexpected(reason: String)

    var errorDescription: String? {
        switch self {
        case .romNotFound(let name):
            "The game “\(name)” couldn't be found."
        case .romNotReadable(let name, _):
            "The game “\(name)” couldn't be opened."
        case .invalidROM:
            "This file isn't a Game Boy game."
        case .unsupportedCartridge:
            "This game's cartridge type isn't supported yet."
        case .invalidInstruction:
            "The game crashed."
        case .saveNotReadable:
            "Your saved game couldn't be loaded."
        case .saveNotWritten:
            "Your progress couldn't be saved."
        case .audioUnavailable:
            "Sound isn't available."
        case .unexpected:
            "Something went wrong."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .romNotFound:
            "Make sure the ROM file is included in the app."
        case .romNotReadable(_, let reason):
            reason
        case .invalidROM:
            "The file is too small to contain a game. It may be damaged or incomplete."
        case .unsupportedCartridge(let type):
            "It uses memory bank controller type 0x\(Self.hex(type)). Only games without one, or with MBC1 or MBC3, can be played."
        case .invalidInstruction(let opcode, let address):
            "It tried to run an instruction that doesn't exist (0x\(Self.hex(opcode)) at address 0x\(Self.hex(address))). This is usually a bug in the emulator, or a damaged ROM."
        case .saveNotReadable(let reason):
            "The game wasn't started, so that the save file isn't overwritten. \(reason)"
        case .saveNotWritten(let reason):
            "You can keep playing, and saving will be tried again. \(reason)"
        case .audioUnavailable(let reason):
            "You can keep playing without sound. \(reason)"
        case .unexpected(let reason):
            reason
        }
    }

    private static func hex<Value: BinaryInteger>(_ value: Value) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, MemoryLayout<Value>.size * 2 - digits.count)) + digits
    }
}
