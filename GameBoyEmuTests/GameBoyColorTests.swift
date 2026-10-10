import Foundation
import Testing
@testable import GameBoyEmu

@Test func cartridgeHeaderDecidesWhetherTheMachineRunsInColor() throws {
    let original = try makeGameBoy()
    #expect(!original.memory.isColorMode)
    #expect(original.cpu.a == 0x01)

    let color = try makeGameBoy(isColor: true)
    #expect(color.memory.isColorMode)
    #expect(color.cpu.a == 0x11) // How a game recognizes a Game Boy Color
}

@Test func colorGamesCanSwitchWorkAndVideoRAMBanks() throws {
    let memory = try makeGameBoy(isColor: true).memory

    memory[0xD000] = 0x11 // Bank 1 is selected at power-on
    memory[0xFF70] = 3
    memory[0xD000] = 0x33
    memory[0xC000] = 0xCC // Bank 0 is not switchable
    #expect(memory[0xD000] == 0x33)
    #expect(memory[0xF000] == 0x33) // Echo RAM follows the selected bank
    memory[0xFF70] = 0 // Bank 0 can't be selected here, it becomes bank 1
    #expect(memory[0xD000] == 0x11)
    #expect(memory[0xC000] == 0xCC)

    memory[0x8000] = 0xAA
    memory[0xFF4F] = 1
    memory[0x8000] = 0xBB
    #expect(memory[0x8000] == 0xBB)
    #expect(memory.videoRAM(bank: 0, address: 0x8000) == 0xAA)
    #expect(memory.videoRAM(bank: 1, address: 0x8000) == 0xBB)
}

@Test func bankRegistersDoNothingOnAnOriginalGameBoy() throws {
    let memory = try makeGameBoy().memory

    memory[0xD000] = 0x11
    memory[0xFF70] = 3
    #expect(memory[0xD000] == 0x11)

    memory[0x8000] = 0xAA
    memory[0xFF4F] = 1
    #expect(memory[0x8000] == 0xAA)
}

@Test func colorPalettesAreWrittenThroughAnIndexAndADataRegister() throws {
    let memory = try makeGameBoy(isColor: true).memory

    memory[0xFF68] = 0x80 | 2 // Start at byte 2 (color 1 of palette 0) and move on after each write
    memory[0xFF69] = 0x1F     // Low byte: red at full strength
    memory[0xFF69] = 0x7C     // High byte: blue at full strength

    #expect(memory.colorPaletteEntry(isObject: false, index: 1) == 0x7C1F)
    #expect(memory[0xFF68] & 0x3F == 4) // The index moved on by itself
}

@Test func colorGamesCanSwitchTheCPUToDoubleSpeed() throws {
    // Request a switch, STOP to carry it out, then two NOPs
    let gameBoy = try makeGameBoy(program: [0x3E, 0x01, 0xE0, 0x4D, 0x10, 0x00, 0x00, 0x00], isColor: true)
    #expect(gameBoy.memory[0xFF4D] & 0x80 == 0)

    #expect(try gameBoy.step().cycles == 8)  // LD A, 1
    #expect(try gameBoy.step().cycles == 12) // LDH (0x4D), A
    #expect(gameBoy.memory[0xFF4D] & 0x81 == 0x01) // Requested, not yet switched

    _ = try gameBoy.step() // STOP
    #expect(gameBoy.memory[0xFF4D] & 0x81 == 0x80) // Switched, and the request is cleared

    // The same NOP now takes half as long as far as the PPU and sound chip are concerned
    #expect(try gameBoy.step().cycles == 2)
}

@Test func stopDoesNotChangeSpeedUnlessASwitchWasRequested() throws {
    let color = try makeGameBoy(program: [0x10, 0x00, 0x00], isColor: true)
    _ = try color.step()
    #expect(try color.step().cycles == 4)

    // An original Game Boy has no speed switch at all
    let original = try makeGameBoy(program: [0x3E, 0x01, 0xE0, 0x4D, 0x10, 0x00, 0x00])
    for _ in 0..<3 { _ = try original.step() }
    #expect(try original.step().cycles == 4)
}

@Test func hdmaCopiesEverythingAtOnceInGeneralPurposeMode() throws {
    let memory = try makeGameBoy(isColor: true).memory
    for offset in 0..<48 { memory[0xC000 + offset] = UInt8(offset + 1) }

    memory[0xFF51] = 0xC0 // Source 0xC000
    memory[0xFF52] = 0x00
    memory[0xFF53] = 0x00 // Destination 0x8000
    memory[0xFF54] = 0x00
    memory[0xFF55] = 0x02 // Three blocks of 16 bytes, now

    #expect(memory[0x8000] == 1)
    #expect(memory[0x802F] == 48)
    #expect(memory[0x8030] == 0)
    #expect(memory[0xFF55] == 0xFF) // Finished
}

@Test func hdmaCopiesOneBlockPerHBlankAndCanBeStopped() throws {
    let memory = try makeGameBoy(isColor: true).memory
    for offset in 0..<48 { memory[0xC000 + offset] = UInt8(offset + 1) }

    memory[0xFF51] = 0xC0
    memory[0xFF52] = 0x00
    memory[0xFF53] = 0x00
    memory[0xFF54] = 0x00
    memory[0xFF55] = 0x82 // Three blocks, one per HBlank
    #expect(memory[0x8000] == 0) // Nothing yet
    #expect(memory[0xFF55] == 0x02) // Running, three blocks to go

    memory.horizontalBlankDidStart()
    #expect(memory[0x800F] == 16)
    #expect(memory[0x8010] == 0)
    #expect(memory[0xFF55] == 0x01)

    // Pokemon Crystal asks for one block too many and then stops the transfer like this.
    // It must not be taken for a request to start a new one.
    memory[0xFF55] = 0x01
    memory.horizontalBlankDidStart()
    #expect(memory[0x8010] == 0)
    #expect(memory[0xFF55] == 0x81) // Stopped, with two blocks left undone
}

@Test func ppuDrawsBackgroundTilesInColor() throws {
    let gameBoy = try makeGameBoy(isColor: true)
    let memory = gameBoy.memory
    memory[0xFF40] = 0x91 // LCD on, tile data at 0x8000, background on

    // Palette 3, color 1: pure green (bits 5-9)
    memory[0xFF68] = 0x80 | (3 * 4 + 1) * 2
    memory[0xFF69] = 0xE0
    memory[0xFF69] = 0x03

    memory[0x9800] = 1           // Top-left tile of the map is tile 1...
    memory[0xFF4F] = 1
    memory[0x9800] = 0x08 | 0x03 // ...taken from VRAM bank 1, drawn with palette 3
    memory[0x8010] = 0b1000_0000 // Tile 1 in bank 1, first row: only the leftmost pixel has color number 1
    memory[0xFF4F] = 0

    try gameBoy.runFrame()

    // Pixels are stored as red, green, blue, unused; so green is the second-lowest byte
    #expect(gameBoy.ppu.displayBuffer[0] == 0xFF00_FF00)
    #expect(gameBoy.ppu.displayBuffer[1] == 0xFFFF_FFFF) // Color 0 of an unset palette is white
}

@Test func backgroundTilesCanClaimPriorityOverSpritesInColor() throws {
    let gameBoy = try makeGameBoy(isColor: true)
    let memory = gameBoy.memory
    memory[0xFF40] = 0x93 // LCD on, background on, sprites on

    memory[0xFF68] = 0x80 | 2 // Background palette 0, color 1: black
    memory[0xFF69] = 0x00
    memory[0xFF69] = 0x00
    memory[0xFF6A] = 0x80 | 2 // Sprite palette 0, color 1: red
    memory[0xFF6B] = 0x1F
    memory[0xFF6B] = 0x00

    memory[0x8010] = 0xFF // Tile 1, first row: all pixels have color number 1
    memory[0x9800] = 1    // Background: tile 1 in the top-left corner...
    memory[0xFF4F] = 1
    memory[0x9800] = 0x80 // ...with priority over sprites
    memory[0xFF4F] = 0

    memory[0xFE00] = 16 // Sprite 0 on top of it, also showing tile 1
    memory[0xFE01] = 8
    memory[0xFE02] = 1

    try gameBoy.runFrame()
    #expect(gameBoy.ppu.displayBuffer[0] == 0xFF00_0000) // The background wins

    memory[0xFF40] = 0x92 // Clearing bit 0 of LCDC puts sprites on top regardless
    try gameBoy.runFrame()
    #expect(gameBoy.ppu.displayBuffer[0] == 0xFF00_00FF)
}

@Test func mbc5SelectsROMBanksWithANineBitNumber() throws {
    var rom = [UInt8](repeating: 0, count: 0x101 * 0x4000)
    rom[0x147] = 0x19 // MBC5
    rom[0x4010] = 1
    rom[0x100 * 0x4000 + 0x10] = 0xAB

    let memory = GameBoyMemory()
    try memory.loadCartridge(data: Data(rom))

    memory[0x2000] = 0x00
    memory[0x3000] = 0x01 // Bank 0x100
    #expect(memory[0x4010] == 0xAB)

    memory[0x3000] = 0x00 // Bank 0 is a valid choice on MBC5
    #expect(memory[0x4010] == rom[0x10])
}

@Test func originalGamesGetThePaletteTheGameBoyColorPicksForThem() throws {
    var rom = [UInt8](repeating: 0, count: 0x8000)

    // Not published by Nintendo: the default combination, with a green and blue background
    try #require(CompatibilityPalettes.palettes(forROM: rom).background == [0x7FFF, 0x1BEF, 0x6180, 0x0000])

    // Pokemon Red: a red background, green for the first sprite palette
    rom.replaceSubrange(0x134..<0x13F, with: Array("POKEMON RED".utf8))
    rom[0x14B] = 0x33 // "See the new licensee code"...
    rom[0x144] = UInt8(ascii: "0") // ...which is "01", Nintendo
    rom[0x145] = UInt8(ascii: "1")
    let red = CompatibilityPalettes.palettes(forROM: rom)
    #expect(red.background == [0x7FFF, 0x421F, 0x1CF2, 0x0000])
    #expect(red.object0 == [0x7FFF, 0x1BEF, 0x0200, 0x0000])
    #expect(red.object1 == [0x7FFF, 0x421F, 0x1CF2, 0x0000])

    // Pokemon Blue shares its title checksum with another game; the fourth letter decides
    rom.replaceSubrange(0x134..<0x144, with: Array("POKEMON BLUE".utf8) + [0, 0, 0, 0])
    #expect(CompatibilityPalettes.palettes(forROM: rom).background == [0x7FFF, 0x7E8C, 0x7C00, 0x0000])

    // And the PPU draws with them: shade 3 of the background is color 3 of that palette
    let gameBoy = GameBoy()
    try gameBoy.loadCartridge(data: Data(rom))
    gameBoy.memory[0xFF47] = 0b11_10_01_00
    gameBoy.memory[0x8000] = 0b0100_0000 // Tile 0, first row: the second pixel has color number 2
    gameBoy.memory[0x8001] = 0b0100_0000 // ...make that color number 3, and leave the first at 0
    try gameBoy.runFrame()
    #expect(gameBoy.ppu.displayBuffer[0] == displayPixel(from: 0x7FFF))
    #expect(gameBoy.ppu.displayBuffer[1] == displayPixel(from: 0x0000))
}
