import Foundation
import Testing
@testable import GameBoyEmu

/// A Game Boy with a blank 32KB cartridge that has `program` at the entry point (0x0100).
private func makeGameBoy(program: [UInt8] = [], isColor: Bool = false) throws -> GameBoy {
    var rom = [UInt8](repeating: 0, count: 0x8000)
    rom[0x143] = isColor ? 0x80 : 0x00 // The header's "made for Game Boy Color" flag
    rom.replaceSubrange(0x100..<(0x100 + program.count), with: program)

    let gameBoy = GameBoy()
    try gameBoy.loadCartridge(data: Data(rom))
    return gameBoy
}

// MARK: - Instruction decoding

@Test func loadSPFromImmediateSetsSPAndLeavesAFAlone() throws {
    let gameBoy = try makeGameBoy(program: [0x31, 0xFE, 0xDF]) // LD SP, 0xDFFE
    let cycles = try gameBoy.cpu.step()

    #expect(gameBoy.cpu.sp == 0xDFFE)
    #expect(gameBoy.cpu.a == 0x01)
    #expect(cycles == 12)
}

@Test func stackPointerArithmeticUsesSP() throws {
    let gameBoy = try makeGameBoy(program: [0x33, 0x3B, 0x3B, 0x39]) // INC SP, DEC SP, DEC SP, ADD HL, SP
    gameBoy.cpu.sp = 0x1000
    gameBoy.cpu.hl = 0x0001
    for _ in 0..<4 { _ = try gameBoy.cpu.step() }

    #expect(gameBoy.cpu.sp == 0x0FFF)
    #expect(gameBoy.cpu.hl == 0x1000)
    #expect(gameBoy.cpu.a == 0x01)
}

@Test func registerField6MeansTheByteAtHLNotTheFlagsRegister() throws {
    // LD B, (HL) / LD (HL), A / ADD A, (HL) / INC (HL) / CB: SET 0, (HL)
    let gameBoy = try makeGameBoy(program: [0x46, 0x77, 0x86, 0x34, 0xCB, 0xC6])
    gameBoy.cpu.hl = 0xC000
    gameBoy.cpu.a = 0x10
    gameBoy.cpu.f = 0xF0
    gameBoy.memory[0xC000] = 0x42

    #expect(try gameBoy.cpu.step() == 8)
    #expect(gameBoy.cpu.b == 0x42)

    #expect(try gameBoy.cpu.step() == 8)
    #expect(gameBoy.memory[0xC000] == 0x10)

    #expect(try gameBoy.cpu.step() == 8)
    #expect(gameBoy.cpu.a == 0x20)

    #expect(try gameBoy.cpu.step() == 12)
    #expect(gameBoy.memory[0xC000] == 0x11)

    #expect(try gameBoy.cpu.step() == 16)
    #expect(gameBoy.memory[0xC000] == 0x11) // Bit 0 was already set
}

@Test func popAFKeepsTheLowerFlagBitsZero() throws {
    let gameBoy = try makeGameBoy(program: [0xC5, 0xF1]) // PUSH BC, POP AF
    gameBoy.cpu.bc = 0x12FF
    _ = try gameBoy.cpu.step()
    _ = try gameBoy.cpu.step()

    #expect(gameBoy.cpu.a == 0x12)
    #expect(gameBoy.cpu.f == 0xF0)
}

// MARK: - Interrupts

@Test func enablingInterruptsDoesNotTouchTheIERegister() throws {
    let gameBoy = try makeGameBoy(program: [0xFB, 0x00, 0xF3]) // EI, NOP, DI
    gameBoy.memory[0xFF0F] = 0
    gameBoy.memory[0xFFFF] = 0x05
    for _ in 0..<3 { _ = try gameBoy.cpu.step() }

    #expect(gameBoy.memory[0xFFFF] == 0x05)
}

@Test func pendingInterruptPushesPCAndJumpsToItsVector() throws {
    let gameBoy = try makeGameBoy()
    gameBoy.cpu.isInterruptMasterEnabled = true
    gameBoy.cpu.sp = 0xDFFE
    gameBoy.memory[0xFFFF] = 0x04 // Only the timer interrupt is enabled
    gameBoy.memory[0xFF0F] = 0x05 // VBlank and timer are both requested

    let cycles = try gameBoy.cpu.step()

    #expect(cycles == 20)
    #expect(gameBoy.cpu.pc == 0x0050) // Timer vector, VBlank was not enabled
    #expect(gameBoy.cpu.sp == 0xDFFC)
    #expect(gameBoy.memory[0xDFFC] == 0x00) // Return address 0x0100, low byte first
    #expect(gameBoy.memory[0xDFFD] == 0x01)
    #expect(gameBoy.memory[0xFF0F] & 0x1F == 0x01) // Only the serviced request is cleared
    #expect(!gameBoy.cpu.isInterruptMasterEnabled)
}

@Test func haltSleepsUntilAnInterruptIsRequested() throws {
    let gameBoy = try makeGameBoy(program: [0x76, 0x3C]) // HALT, INC A
    gameBoy.memory[0xFF0F] = 0
    gameBoy.memory[0xFFFF] = 0x01
    gameBoy.cpu.a = 0

    for _ in 0..<10 { _ = try gameBoy.cpu.step() }
    #expect(gameBoy.cpu.isClockHalted)
    #expect(gameBoy.cpu.a == 0)

    gameBoy.memory[0xFF0F] = 0x01
    _ = try gameBoy.cpu.step()
    #expect(!gameBoy.cpu.isClockHalted)
    #expect(gameBoy.cpu.a == 1)
}

// MARK: - Memory

@Test func writingToROMSwitchesBanksInsteadOfChangingTheROM() throws {
    var rom = [UInt8](repeating: 0, count: 4 * 0x4000)
    rom[0x147] = 0x01 // MBC1
    for bank in 0..<4 { rom[bank * 0x4000 + 0x10] = UInt8(bank) }

    let memory = GameBoyMemory()
    try memory.loadCartridge(data: Data(rom))
    #expect(memory[0x4010] == 1)

    memory[0x2000] = 3
    #expect(memory[0x2000] == 0)
    #expect(memory[0x0010] == 0)
    #expect(memory[0x4010] == 3)

    memory[0x2000] = 0 // Bank 0 can't be selected, it becomes bank 1
    #expect(memory[0x4010] == 1)
}

@Test func cartridgeRAMSurvivesBeingSavedAndLoadedAgain() throws {
    var rom = [UInt8](repeating: 0, count: 4 * 0x4000)
    rom[0x147] = 0x13 // MBC3 with RAM and battery

    let memory = GameBoyMemory()
    try memory.loadCartridge(data: Data(rom))
    #expect(memory.hasBattery)
    #expect(!memory.hasUnsavedExternalRam)

    memory[0xA000] = 0x11
    memory[0x4000] = 2 // Switch to RAM bank 2
    memory[0xBFFF] = 0x22
    #expect(memory.hasUnsavedExternalRam)

    let restored = GameBoyMemory()
    try restored.loadCartridge(data: Data(rom), save: Data(memory.externalRam))

    #expect(!restored.hasUnsavedExternalRam)
    #expect(restored[0xA000] == 0x11)
    restored[0x4000] = 2
    #expect(restored[0xBFFF] == 0x22)
}

@Test func dmaTransferCopiesSpriteDataIntoOAM() throws {
    let memory = GameBoyMemory()
    memory[0xC000] = 0xAA
    memory[0xC09F] = 0xBB
    memory[0xFF46] = 0xC0

    #expect(memory[0xFE00] == 0xAA)
    #expect(memory[0xFE9F] == 0xBB)
}

@Test func joypadReadsPressedButtonsAsZeroBits() throws {
    let gameBoy = try makeGameBoy()
    #expect(gameBoy.memory[0xFF00] & 0x0F == 0x0F) // Nothing pressed

    gameBoy.memory.joypad.startButtonPressed = true
    gameBoy.memory.joypad.dPadState = .left

    gameBoy.memory[0xFF00] = 0x10 // Select the action buttons
    #expect(gameBoy.memory[0xFF00] & 0x0F == 0b0111)

    gameBoy.memory[0xFF00] = 0x20 // Select the d-pad
    #expect(gameBoy.memory[0xFF00] & 0x0F == 0b1101)
}

// MARK: - Timer

@Test func timerOverflowReloadsAndRequestsTheTimerInterrupt() throws {
    let memory = GameBoyMemory()
    memory[0xFF0F] = 0
    memory[0xFF04] = 0    // Reset DIV
    memory[0xFF06] = 0xF0 // TMA
    memory[0xFF05] = 0xFF // TIMA
    memory[0xFF07] = 0x05 // Enabled, one increment every 16 cycles

    memory.tickClock(cycles: 12)
    #expect(memory[0xFF05] == 0xFF)
    #expect(memory[0xFF0F] & 0x04 == 0)

    memory.tickClock(cycles: 4)
    #expect(memory[0xFF05] == 0xF0)
    #expect(memory[0xFF0F] & 0x04 != 0)
}

// MARK: - PPU

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

// MARK: - APU

/// Runs the APU for the given number of seconds of emulated time.
private func run(_ apu: GameBoyAPU, seconds: Double) {
    for _ in 0..<Int(seconds * GameBoyClock.frequency / 4) {
        apu.step(cycles: 4)
    }
}

@Test func pulseChannelPlaysASquareWaveAtTheRequestedPitch() throws {
    let apu = GameBoyAPU()
    apu[0xFF25] = 0x22 // Pulse 2 to both speakers
    apu[0xFF16] = 0x80 // 50% duty
    apu[0xFF17] = 0xF0 // Full volume, no fade
    apu[0xFF18] = 0xD6 // Frequency 1750: 131072 / (2048 - 1750) = 440 Hz
    apu[0xFF19] = 0x86 // Trigger

    #expect(apu[0xFF26] & 0x02 != 0) // NR52 reports pulse 2 as playing

    run(apu, seconds: 1)

    let left = stride(from: 0, to: apu.pendingSamples.count, by: 2).map { apu.pendingSamples[$0] }
    #expect(left.count == GameBoyAPU.sampleRate)

    let risingEdges = zip(left, left.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
    #expect((438...442).contains(risingEdges))
    #expect(left.max()! > 0.05)
}

@Test func lengthCounterSwitchesTheChannelOff() throws {
    let apu = GameBoyAPU()
    apu[0xFF17] = 0xF0
    apu[0xFF16] = 0x3C // Length 64 - 60 = 4 ticks of 1/256 s
    apu[0xFF19] = 0xC0 // Trigger with the length counter enabled

    run(apu, seconds: 0.01)
    #expect(apu[0xFF26] & 0x02 != 0)

    run(apu, seconds: 0.01)
    #expect(apu[0xFF26] & 0x02 == 0)
}

@Test func envelopeFadesANoteOut() throws {
    let apu = GameBoyAPU()
    apu[0xFF25] = 0x22
    apu[0xFF16] = 0x80
    apu[0xFF17] = 0xF1 // Start at full volume, one step down every 1/64 s
    apu[0xFF18] = 0xD6
    apu[0xFF19] = 0x86

    run(apu, seconds: 0.05)
    let loudness = apu.pendingSamples.map(abs).max()!
    apu.pendingSamples.removeAll()

    run(apu, seconds: 0.5) // 15 steps take 15/64 s, so the note has faded out by now
    apu.pendingSamples.removeAll()
    run(apu, seconds: 0.05)

    #expect(loudness > 0.05)
    #expect(apu.pendingSamples.map(abs).max()! < 0.001)
}

@Test func waveAndNoiseChannelsProduceSound() throws {
    let apu = GameBoyAPU()
    apu[0xFF25] = 0x44 // Wave channel only
    for address in 0xFF30...0xFF3F {
        apu[address] = address < 0xFF38 ? 0xFF : 0x00 // A square wave, as samples
    }
    apu[0xFF1A] = 0x80 // Wave channel on
    apu[0xFF1C] = 0x20 // 100% volume
    apu[0xFF1D] = 0xD6
    apu[0xFF1E] = 0x86
    run(apu, seconds: 0.05)
    #expect(apu.pendingSamples.map(abs).max()! > 0.05)

    apu.pendingSamples.removeAll()
    apu[0xFF25] = 0x88 // Noise channel only
    apu[0xFF21] = 0xF0
    apu[0xFF22] = 0x22
    apu[0xFF23] = 0x80
    run(apu, seconds: 0.05)
    #expect(apu.pendingSamples.map(abs).max()! > 0.05)
}

@Test func poweringTheAPUOffClearsItsRegisters() throws {
    let apu = GameBoyAPU()
    apu[0xFF17] = 0xF0
    apu[0xFF19] = 0x80
    apu[0xFF26] = 0x00 // Power off

    #expect(apu[0xFF26] == 0x70)
    #expect(apu[0xFF17] == 0x00)

    apu[0xFF17] = 0xF0 // Ignored while the power is off
    #expect(apu[0xFF17] == 0x00)
}

// MARK: - Game Boy Color

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

// MARK: - Joypad

@Test func aQuickTapIsHeldLongEnoughForTheGameToSeeIt() throws {
    var down = JoypadState()
    down.dPadState = .down

    var queue = JoypadQueue()
    #expect(queue.advanceFrame() == JoypadState()) // Nothing pressed yet

    // A tap: pressed and released again before the next frame
    queue.report(down)
    queue.report(JoypadState())

    for _ in 0..<JoypadQueue.minimumFrames {
        #expect(queue.advanceFrame() == down)
    }
    #expect(queue.advanceFrame() == JoypadState())
}

@Test func aPressAfterAPauseTakesEffectOnTheNextFrame() throws {
    var a = JoypadState()
    a.aButtonPressed = true

    var queue = JoypadQueue()
    for _ in 0..<10 { _ = queue.advanceFrame() }

    queue.report(a)
    #expect(queue.advanceFrame() == a)
}

// MARK: - Catalogue

@Test func catalogueNamesWellKnownGamesFromTheirHeaderTitles() throws {
    #expect(GameCatalogue.name(headerTitle: "POKEMON RED", isColor: false) == "Pokémon Red")
    #expect(GameCatalogue.name(headerTitle: "MARIOLAND2", isColor: false) == "Super Mario Land 2: 6 Golden Coins")

    // Color-era headers run the title and the product code together
    #expect(GameCatalogue.name(headerTitle: "POKEMON_GLDAAUE", isColor: true) == "Pokémon Gold")

    // The Color re-release of Link's Awakening kept the original's header title
    #expect(GameCatalogue.name(headerTitle: "ZELDA", isColor: false) == "The Legend of Zelda: Link's Awakening")
    #expect(GameCatalogue.name(headerTitle: "ZELDA", isColor: true) == "The Legend of Zelda: Link's Awakening DX")

    #expect(GameCatalogue.name(headerTitle: "SOME HOMEBREW", isColor: false) == nil)
}

// MARK: - Emulator

@Test func emulatorDeliversFramesUntilItsConsumerStops() async throws {
    let emulator = Emulator()
    var frames = 0

    // Leaving the loop ends the stream, which is what stops the emulation
    for try await frame in emulator.run(rom: Data(count: 0x8000), saveURL: nil) {
        #expect(frame.count == displayBufferWidth * displayBufferHeight)
        frames += 1
        if frames == 3 {
            break
        }
    }

    #expect(frames == 3)
}

@Test func emulatorCarriesOnWhereItWasStopped() async throws {
    // A program that counts in register-backed RAM: INC (HL) in a loop, with HL = 0xC000
    var rom = [UInt8](repeating: 0, count: 0x8000)
    rom.replaceSubrange(0x100..<0x106, with: [0x21, 0x00, 0xC0, 0x34, 0x18, 0xFD]) // LD HL; INC (HL); JR -3

    let emulator = Emulator()
    for try await _ in emulator.run(rom: Data(rom), saveURL: nil) { break }

    // Running again must not reload the cartridge. Proof: this "ROM" isn't one, and loading
    // it would throw, but the machine already has its cartridge and simply continues.
    var frames = 0
    for try await _ in emulator.run(rom: Data(), saveURL: nil) {
        frames += 1
        if frames == 2 { break }
    }
    #expect(frames == 2)
}

// MARK: - Errors

@Test func runningIntoANonexistentOpcodeThrows() throws {
    let gameBoy = try makeGameBoy(program: [0x00, 0xDD]) // NOP, then an opcode that doesn't exist
    _ = try gameBoy.cpu.step()

    #expect(throws: GameBoyError.invalidInstruction(opcode: 0xDD, address: 0x0101)) {
        try gameBoy.cpu.step()
    }
}

@Test func loadingSomethingThatIsNotASupportedROMThrows() throws {
    let memory = GameBoyMemory()

    #expect(throws: GameBoyError.invalidROM) {
        try memory.loadCartridge(data: Data(count: 16))
    }

    var rom = [UInt8](repeating: 0, count: 0x8000)
    rom[0x147] = 0x22 // MBC7
    #expect(throws: GameBoyError.unsupportedCartridge(type: 0x22)) {
        try memory.loadCartridge(data: Data(rom))
    }
}

@Test func emulatorEndsItsStreamWithTheErrorThatStoppedIt() async {
    var rom = [UInt8](repeating: 0, count: 0x8000)
    rom[0x100] = 0xDD

    await #expect(throws: GameBoyError.invalidInstruction(opcode: 0xDD, address: 0x0100)) {
        for try await _ in Emulator().run(rom: Data(rom), saveURL: nil) {}
    }
}

// MARK: - Test ROMs

/// Blargg's cpu_instrs exercises every instruction and reports the result over the link cable.
/// The tests run inside the app, so the ROM comes from the app bundle. The ROMs are not
/// checked in, so this only runs when the file is present.
@Test(.enabled(if: Bundle.main.url(forResource: "cpu_instrs", withExtension: "gb") != nil))
func cpuInstructionTestROMPasses() throws {
    let gameBoy = GameBoy()
    let url = try #require(Bundle.main.url(forResource: "cpu_instrs", withExtension: "gb"))
    try gameBoy.memory.loadCartridge(data: try Data(contentsOf: url))

    var output = ""
    var cycles = 0
    while !output.contains("Passed all tests") && !output.contains("Failed") && cycles < 400_000_000 {
        cycles += try gameBoy.step().cycles
        if !gameBoy.memory.serialOutput.isEmpty {
            output += String(decoding: gameBoy.memory.serialOutput, as: UTF8.self)
            gameBoy.memory.serialOutput.removeAll()
        }
    }

    #expect(output.contains("Passed all tests"), "Serial output: \(output)")
}
