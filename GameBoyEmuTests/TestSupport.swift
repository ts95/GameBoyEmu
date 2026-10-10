import Foundation
import Testing
@testable import GameBoyEmu

/// A Game Boy with a blank 32KB cartridge that has `program` at the entry point (0x0100).
func makeGameBoy(program: [UInt8] = [], isColor: Bool = false) throws -> GameBoy {
    var rom = [UInt8](repeating: 0, count: 0x8000)
    rom[0x143] = isColor ? 0x80 : 0x00 // The header's "made for Game Boy Color" flag
    rom.replaceSubrange(0x100..<(0x100 + program.count), with: program)

    let gameBoy = GameBoy()
    try gameBoy.loadCartridge(data: Data(rom))
    return gameBoy
}
