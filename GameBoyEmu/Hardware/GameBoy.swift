//
//  GameBoy.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

/// The class that ties all of the Game Boy's components together into a cohesive whole.
///
/// This is the machine itself and nothing else: it is synchronous, knows nothing about real
/// time, threads or the UI, and only moves when someone calls `step()`. `Emulator` is what
/// runs it at 60 frames per second.
final class GameBoy {
    /// T cycles per frame: 154 scanlines of 456 cycles each, which gives ~59.7 frames per second.
    static let cyclesPerFrame = 154 * 456

    let memory: GameBoyMemory
    let cpu: GameBoyCPU<GameBoyMemory>
    let ppu: GameBoyPPU<GameBoyMemory>

    init() {
        let memory = GameBoyMemory()

        self.memory = memory
        self.cpu = GameBoyCPU(addressBus: memory)
        self.ppu = GameBoyPPU(addressBus: memory)
    }

    /// Inserts a cartridge and puts the CPU in the state the boot ROM would leave it in.
    ///
    /// - Parameters:
    ///   - data: The cartridge ROM.
    ///   - save: The contents of the cartridge RAM from an earlier session, if any.
    /// - Throws: `GameBoyError` if the data isn't a ROM this emulator can run.
    func loadCartridge(data: Data, save: Data? = nil) throws {
        try memory.loadCartridge(data: data, save: save)

        if memory.isColorMode {
            // A game finds out it is running on a Game Boy Color by looking at register A
            (cpu.a, cpu.f) = (0x11, 0x80)
            (cpu.bc, cpu.de, cpu.hl) = (0x0000, 0xFF56, 0x000D)
        }
    }

    /// Runs one CPU instruction and lets the rest of the hardware catch up by the same
    /// number of cycles. This is the heartbeat of the emulator: the CPU, PPU, timer and APU
    /// are independent machines that only stay in sync because they count the same cycles.
    ///
    /// - Returns: Whether the PPU completed a frame, and how many cycles passed for the PPU.
    @discardableResult
    func step() throws -> (frameCompleted: Bool, cycles: Int) {
        let cpuCycles = try cpu.step()
        memory.tickClock(cycles: cpuCycles)

        // In double-speed mode the CPU and the timer run at twice the clock rate, while the
        // PPU and the sound chip keep their normal pace. So the same instruction takes half
        // as long from their point of view, and the CPU gets twice as much done per frame.
        let tCycles = memory.isDoubleSpeed ? cpuCycles / 2 : cpuCycles
        memory.apu.step(cycles: tCycles)
        return (ppu.step(cycles: tCycles), tCycles)
    }

    /// Runs the emulation until the PPU has finished drawing a frame.
    func runFrame() throws {
        // The cycle limit ends the frame when the game has switched the LCD off
        var cycles = 0
        while cycles < GameBoy.cyclesPerFrame {
            let result = try step()
            if result.frameCompleted {
                break
            }
            cycles += result.cycles
        }
    }
}
