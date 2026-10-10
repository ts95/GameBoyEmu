import Foundation
import Testing
@testable import GameBoyEmu

/// A Game Boy with a blank 32KB cartridge that has `program` at the entry point (0x0100).
private func makeGameBoy(program: [UInt8] = []) -> GameBoy {
    var rom = [UInt8](repeating: 0, count: 0x8000)
    rom.replaceSubrange(0x100..<(0x100 + program.count), with: program)

    let gameBoy = GameBoy()
    gameBoy.memory.loadCartridge(data: Data(rom))
    return gameBoy
}

// MARK: - Instruction decoding

@Test func loadSPFromImmediateSetsSPAndLeavesAFAlone() {
    let gameBoy = makeGameBoy(program: [0x31, 0xFE, 0xDF]) // LD SP, 0xDFFE
    let cycles = gameBoy.cpu.step()

    #expect(gameBoy.cpu.sp == 0xDFFE)
    #expect(gameBoy.cpu.a == 0x01)
    #expect(cycles == 12)
}

@Test func stackPointerArithmeticUsesSP() {
    let gameBoy = makeGameBoy(program: [0x33, 0x3B, 0x3B, 0x39]) // INC SP, DEC SP, DEC SP, ADD HL, SP
    gameBoy.cpu.sp = 0x1000
    gameBoy.cpu.hl = 0x0001
    for _ in 0..<4 { _ = gameBoy.cpu.step() }

    #expect(gameBoy.cpu.sp == 0x0FFF)
    #expect(gameBoy.cpu.hl == 0x1000)
    #expect(gameBoy.cpu.a == 0x01)
}

@Test func registerField6MeansTheByteAtHLNotTheFlagsRegister() {
    // LD B, (HL) / LD (HL), A / ADD A, (HL) / INC (HL) / CB: SET 0, (HL)
    let gameBoy = makeGameBoy(program: [0x46, 0x77, 0x86, 0x34, 0xCB, 0xC6])
    gameBoy.cpu.hl = 0xC000
    gameBoy.cpu.a = 0x10
    gameBoy.cpu.f = 0xF0
    gameBoy.memory[0xC000] = 0x42

    #expect(gameBoy.cpu.step() == 8)
    #expect(gameBoy.cpu.b == 0x42)

    #expect(gameBoy.cpu.step() == 8)
    #expect(gameBoy.memory[0xC000] == 0x10)

    #expect(gameBoy.cpu.step() == 8)
    #expect(gameBoy.cpu.a == 0x20)

    #expect(gameBoy.cpu.step() == 12)
    #expect(gameBoy.memory[0xC000] == 0x11)

    #expect(gameBoy.cpu.step() == 16)
    #expect(gameBoy.memory[0xC000] == 0x11) // Bit 0 was already set
}

@Test func popAFKeepsTheLowerFlagBitsZero() {
    let gameBoy = makeGameBoy(program: [0xC5, 0xF1]) // PUSH BC, POP AF
    gameBoy.cpu.bc = 0x12FF
    _ = gameBoy.cpu.step()
    _ = gameBoy.cpu.step()

    #expect(gameBoy.cpu.a == 0x12)
    #expect(gameBoy.cpu.f == 0xF0)
}

// MARK: - Interrupts

@Test func enablingInterruptsDoesNotTouchTheIERegister() {
    let gameBoy = makeGameBoy(program: [0xFB, 0x00, 0xF3]) // EI, NOP, DI
    gameBoy.memory[0xFF0F] = 0
    gameBoy.memory[0xFFFF] = 0x05
    for _ in 0..<3 { _ = gameBoy.cpu.step() }

    #expect(gameBoy.memory[0xFFFF] == 0x05)
}

@Test func pendingInterruptPushesPCAndJumpsToItsVector() {
    let gameBoy = makeGameBoy()
    gameBoy.cpu.isInterruptMasterEnabled = true
    gameBoy.cpu.sp = 0xDFFE
    gameBoy.memory[0xFFFF] = 0x04 // Only the timer interrupt is enabled
    gameBoy.memory[0xFF0F] = 0x05 // VBlank and timer are both requested

    let cycles = gameBoy.cpu.step()

    #expect(cycles == 20)
    #expect(gameBoy.cpu.pc == 0x0050) // Timer vector, VBlank was not enabled
    #expect(gameBoy.cpu.sp == 0xDFFC)
    #expect(gameBoy.memory[0xDFFC] == 0x00) // Return address 0x0100, low byte first
    #expect(gameBoy.memory[0xDFFD] == 0x01)
    #expect(gameBoy.memory[0xFF0F] & 0x1F == 0x01) // Only the serviced request is cleared
    #expect(!gameBoy.cpu.isInterruptMasterEnabled)
}

@Test func haltSleepsUntilAnInterruptIsRequested() {
    let gameBoy = makeGameBoy(program: [0x76, 0x3C]) // HALT, INC A
    gameBoy.memory[0xFF0F] = 0
    gameBoy.memory[0xFFFF] = 0x01
    gameBoy.cpu.a = 0

    for _ in 0..<10 { _ = gameBoy.cpu.step() }
    #expect(gameBoy.cpu.isClockHalted)
    #expect(gameBoy.cpu.a == 0)

    gameBoy.memory[0xFF0F] = 0x01
    _ = gameBoy.cpu.step()
    #expect(!gameBoy.cpu.isClockHalted)
    #expect(gameBoy.cpu.a == 1)
}

// MARK: - Memory

@Test func writingToROMSwitchesBanksInsteadOfChangingTheROM() {
    var rom = [UInt8](repeating: 0, count: 4 * 0x4000)
    rom[0x147] = 0x01 // MBC1
    for bank in 0..<4 { rom[bank * 0x4000 + 0x10] = UInt8(bank) }

    let memory = GameBoyMemory()
    memory.loadCartridge(data: Data(rom))
    #expect(memory[0x4010] == 1)

    memory[0x2000] = 3
    #expect(memory[0x2000] == 0)
    #expect(memory[0x0010] == 0)
    #expect(memory[0x4010] == 3)

    memory[0x2000] = 0 // Bank 0 can't be selected, it becomes bank 1
    #expect(memory[0x4010] == 1)
}

@Test func dmaTransferCopiesSpriteDataIntoOAM() {
    let memory = GameBoyMemory()
    memory[0xC000] = 0xAA
    memory[0xC09F] = 0xBB
    memory[0xFF46] = 0xC0

    #expect(memory[0xFE00] == 0xAA)
    #expect(memory[0xFE9F] == 0xBB)
}

@Test func joypadReadsPressedButtonsAsZeroBits() {
    let gameBoy = makeGameBoy()
    #expect(gameBoy.memory[0xFF00] & 0x0F == 0x0F) // Nothing pressed

    gameBoy.joypad.startButtonPressed = true
    gameBoy.joypad.dPadState = .left

    gameBoy.memory[0xFF00] = 0x10 // Select the action buttons
    #expect(gameBoy.memory[0xFF00] & 0x0F == 0b0111)

    gameBoy.memory[0xFF00] = 0x20 // Select the d-pad
    #expect(gameBoy.memory[0xFF00] & 0x0F == 0b1101)
}

// MARK: - Timer

@Test func timerOverflowReloadsAndRequestsTheTimerInterrupt() {
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

@Test func ppuReportsItsScanlineAndRequestsVBlank() {
    let gameBoy = makeGameBoy()
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

@Test func ppuDrawsBackgroundTilesThroughThePalette() {
    let gameBoy = makeGameBoy()
    gameBoy.memory[0xFF40] = 0x91 // LCD on, tile data at 0x8000, background on
    gameBoy.memory[0xFF47] = 0b00_01_10_11 // Palette that inverts the color numbers
    gameBoy.memory[0x9800] = 1 // Top-left tile of the map is tile 1
    gameBoy.memory[0x8010] = 0b1000_0000 // Tile 1, first row: leftmost pixel has color number 1...
    gameBoy.memory[0x8011] = 0b0100_0000 // ...and the second pixel has color number 2

    gameBoy.runFrame()

    #expect(gameBoy.ppu.displayBuffer[0] == 2)
    #expect(gameBoy.ppu.displayBuffer[1] == 1)
    #expect(gameBoy.ppu.displayBuffer[2] == 3) // Color number 0
}

@Test func ppuDrawsSprites() {
    let gameBoy = makeGameBoy()
    gameBoy.memory[0xFF40] = 0x93 // LCD on, background on, sprites on
    gameBoy.memory[0xFF47] = 0x00 // Background is all color 0
    gameBoy.memory[0xFF48] = 0b11_10_01_00
    gameBoy.memory[0x8010] = 0xFF // Tile 1, first row: all pixels have color number 3
    gameBoy.memory[0x8011] = 0xFF
    gameBoy.memory[0xFE00] = 16 + 2 // Sprite 0 at screen row 2...
    gameBoy.memory[0xFE01] = 8 + 4  // ...and screen column 4
    gameBoy.memory[0xFE02] = 1
    gameBoy.memory[0xFE03] = 0x40 // Flipped vertically, so tile row 0 lands on the sprite's last row

    gameBoy.runFrame()

    #expect(gameBoy.ppu.displayBuffer[2 * 160 + 4] == 0)
    #expect(gameBoy.ppu.displayBuffer[9 * 160 + 4] == 3)
    #expect(gameBoy.ppu.displayBuffer[9 * 160 + 11] == 3)
    #expect(gameBoy.ppu.displayBuffer[9 * 160 + 12] == 0)
}

// MARK: - APU

/// Runs the APU for the given number of seconds of emulated time.
private func run(_ apu: GameBoyAPU, seconds: Double) {
    for _ in 0..<Int(seconds * GameBoyClock.frequency / 4) {
        apu.step(cycles: 4)
    }
}

@Test func pulseChannelPlaysASquareWaveAtTheRequestedPitch() {
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

@Test func lengthCounterSwitchesTheChannelOff() {
    let apu = GameBoyAPU()
    apu[0xFF17] = 0xF0
    apu[0xFF16] = 0x3C // Length 64 - 60 = 4 ticks of 1/256 s
    apu[0xFF19] = 0xC0 // Trigger with the length counter enabled

    run(apu, seconds: 0.01)
    #expect(apu[0xFF26] & 0x02 != 0)

    run(apu, seconds: 0.01)
    #expect(apu[0xFF26] & 0x02 == 0)
}

@Test func envelopeFadesANoteOut() {
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

@Test func waveAndNoiseChannelsProduceSound() {
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

@Test func poweringTheAPUOffClearsItsRegisters() {
    let apu = GameBoyAPU()
    apu[0xFF17] = 0xF0
    apu[0xFF19] = 0x80
    apu[0xFF26] = 0x00 // Power off

    #expect(apu[0xFF26] == 0x70)
    #expect(apu[0xFF17] == 0x00)

    apu[0xFF17] = 0xF0 // Ignored while the power is off
    #expect(apu[0xFF17] == 0x00)
}

// MARK: - Test ROMs

/// Blargg's cpu_instrs exercises every instruction and reports the result over the link cable.
/// The tests run inside the app, so the ROM comes from the app bundle. The ROMs are not
/// checked in, so this only runs when the file is present.
@Test(.enabled(if: Bundle.main.url(forResource: "cpu_instrs", withExtension: "gb") != nil))
func cpuInstructionTestROMPasses() throws {
    let gameBoy = GameBoy()
    let url = try #require(Bundle.main.url(forResource: "cpu_instrs", withExtension: "gb"))
    gameBoy.memory.loadCartridge(data: try Data(contentsOf: url))

    var output = ""
    var cycles = 0
    while !output.contains("Passed all tests") && !output.contains("Failed") && cycles < 400_000_000 {
        cycles += gameBoy.step().cycles
        if !gameBoy.memory.serialOutput.isEmpty {
            output += String(decoding: gameBoy.memory.serialOutput, as: UTF8.self)
            gameBoy.memory.serialOutput.removeAll()
        }
    }

    #expect(output.contains("Passed all tests"), "Serial output: \(output)")
}
