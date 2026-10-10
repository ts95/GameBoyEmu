import Foundation
import Testing
@testable import GameBoyEmu

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
