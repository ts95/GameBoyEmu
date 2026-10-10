import Foundation
import Testing
@testable import GameBoyEmu

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
