import Foundation
import Testing
@testable import GameBoyEmu

@Test func ppuReportsItsScanlineAndRequestsVBlank() throws {
    let gameBoy = try makeGameBoy()
    gameBoy.memory[0xFF0F] = 0

    gameBoy.ppu.step(cycles: 456)
    #expect(gameBoy.memory[0xFF44] == 0) // Mode changes are checked once per step
    for _ in 0..<3 { gameBoy.ppu.step(cycles: 0) }
    #expect(gameBoy.memory[0xFF44] == 1)

    var frameCompleted = false
    while !frameCompleted {
        frameCompleted = gameBoy.ppu.step(cycles: 4)
    }

    #expect(gameBoy.memory[0xFF44] == 144)
    #expect(gameBoy.memory[0xFF41] & 0x03 == 1) // STAT reports mode 1, VBlank
    #expect(gameBoy.memory[0xFF0F] & 0x01 != 0)
}

/// The pixel an original Game Boy game gets for a background shade (0-3), which depends on
/// the color palette the console picked for the cartridge.
private func backgroundShade(_ shade: Int, of gameBoy: GameBoy) -> UInt32 {
    displayPixel(from: gameBoy.memory.colorPaletteEntry(isObject: false, index: shade))
}

@Test func ppuDrawsBackgroundTilesThroughThePalette() throws {
    let gameBoy = try makeGameBoy()
    gameBoy.memory[0xFF40] = 0x91 // LCD on, tile data at 0x8000, background on
    gameBoy.memory[0xFF47] = 0b00_01_10_11 // Palette that inverts the color numbers
    gameBoy.memory[0x9800] = 1 // Top-left tile of the map is tile 1
    gameBoy.memory[0x8010] = 0b1000_0000 // Tile 1, first row: leftmost pixel has color number 1...
    gameBoy.memory[0x8011] = 0b0100_0000 // ...and the second pixel has color number 2

    try gameBoy.runFrame()

    #expect(gameBoy.ppu.displayBuffer[0] == backgroundShade(2, of: gameBoy))
    #expect(gameBoy.ppu.displayBuffer[1] == backgroundShade(1, of: gameBoy))
    #expect(gameBoy.ppu.displayBuffer[2] == backgroundShade(3, of: gameBoy)) // Color number 0
}

@Test func ppuDrawsSprites() throws {
    let gameBoy = try makeGameBoy()
    gameBoy.memory[0xFF40] = 0x93 // LCD on, background on, sprites on
    gameBoy.memory[0xFF47] = 0x00 // Background is all color 0
    gameBoy.memory[0xFF48] = 0b11_10_01_00
    gameBoy.memory[0x8010] = 0xFF // Tile 1, first row: all pixels have color number 3
    gameBoy.memory[0x8011] = 0xFF
    gameBoy.memory[0xFE00] = 16 + 2 // Sprite 0 at screen row 2...
    gameBoy.memory[0xFE01] = 8 + 4  // ...and screen column 4
    gameBoy.memory[0xFE02] = 1
    gameBoy.memory[0xFE03] = 0x40 // Flipped vertically, so tile row 0 lands on the sprite's last row

    try gameBoy.runFrame()

    #expect(gameBoy.ppu.displayBuffer[2 * 160 + 4] == backgroundShade(0, of: gameBoy))
    #expect(gameBoy.ppu.displayBuffer[9 * 160 + 4] == displayPixel(from: gameBoy.memory.colorPaletteEntry(isObject: true, index: 3)))
    #expect(gameBoy.ppu.displayBuffer[9 * 160 + 11] == displayPixel(from: gameBoy.memory.colorPaletteEntry(isObject: true, index: 3)))
    #expect(gameBoy.ppu.displayBuffer[9 * 160 + 12] == backgroundShade(0, of: gameBoy))
}
