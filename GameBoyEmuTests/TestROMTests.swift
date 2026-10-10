import Foundation
import Testing
@testable import GameBoyEmu

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
