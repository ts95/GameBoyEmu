import Foundation
import Testing
@testable import GameBoyEmu

// MARK: - Serial port

@Test func aTransferWithNoCableFinishesAndReceivesAllOnes() throws {
    let memory = try makeGameBoy().memory
    memory[0xFF0F] = 0

    memory[0xFF01] = 0x42
    memory[0xFF02] = 0x81 // Start a transfer, providing the clock

    memory.tickClock(cycles: 4092)
    #expect(memory[0xFF02] & 0x80 != 0) // Still going: 8 bits take 4096 cycles
    #expect(memory[0xFF0F] & 0x08 == 0)

    memory.tickClock(cycles: 4)
    #expect(memory[0xFF01] == 0xFF)
    #expect(memory[0xFF02] & 0x80 == 0)
    #expect(memory[0xFF0F] & 0x08 != 0) // The serial interrupt
}

@Test func aConsoleWaitingForTheOtherClockWaitsForever() throws {
    let memory = try makeGameBoy().memory
    memory[0xFF0F] = 0

    memory[0xFF01] = 0x42
    memory[0xFF02] = 0x80 // Start a transfer, but let the other console provide the clock

    memory.tickClock(cycles: 100_000)
    #expect(memory[0xFF01] == 0x42)
    #expect(memory[0xFF02] & 0x80 != 0)
    #expect(memory[0xFF0F] & 0x08 == 0)
}

// MARK: - Link cable

@Test func linkedConsolesSwapABytePerTransfer() throws {
    let first = try makeGameBoy()
    let second = try makeGameBoy()
    let cable = LinkCable(first, second)
    first.memory[0xFF0F] = 0
    second.memory[0xFF0F] = 0

    second.memory[0xFF01] = 0x34
    second.memory[0xFF02] = 0x80 // Waits for the clock
    first.memory[0xFF01] = 0x12
    first.memory[0xFF02] = 0x81 // Provides it

    try cable.run(cycles: 4200)

    #expect(first.memory[0xFF01] == 0x34)
    #expect(second.memory[0xFF01] == 0x12)
    for memory in [first.memory, second.memory] {
        #expect(memory[0xFF02] & 0x80 == 0)
        #expect(memory[0xFF0F] & 0x08 != 0)
    }
}

@Test func aConsoleThatIsNotListeningIsLeftAlone() throws {
    let first = try makeGameBoy()
    let second = try makeGameBoy()
    let cable = LinkCable(first, second)
    second.memory[0xFF0F] = 0

    second.memory[0xFF01] = 0x34 // No transfer set up on this side
    first.memory[0xFF01] = 0x12
    first.memory[0xFF02] = 0x81

    try cable.run(cycles: 4200)

    #expect(first.memory[0xFF01] == 0xFF)
    #expect(second.memory[0xFF01] == 0x34)
    #expect(second.memory[0xFF0F] & 0x08 == 0)
}

@Test func linkedConsolesStayInStep() throws {
    // Each console counts in RAM as fast as it can: INC (HL) in a loop, with HL = 0xC000
    let program: [UInt8] = [0x21, 0x00, 0xC0, 0x34, 0x18, 0xFD]
    let first = try makeGameBoy(program: program)
    let second = try makeGameBoy(program: program)
    let cable = LinkCable(first, second)

    try cable.run(cycles: 100_000)

    // Having run the same program for the same time, they must have got equally far
    #expect(first.memory[0xC000] == second.memory[0xC000])
    #expect(first.cpu.pc == second.cpu.pc)
}

@Test func unpluggingTheCableLeavesBothConsolesOnTheirOwn() throws {
    let first = try makeGameBoy()
    let second = try makeGameBoy()
    do {
        _ = LinkCable(first, second)
    }
    #expect(first.memory.serial.partner == nil)
    #expect(second.memory.serial.partner == nil)
}
