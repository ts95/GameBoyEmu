import Foundation
import Testing
@testable import GameBoyEmu

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
