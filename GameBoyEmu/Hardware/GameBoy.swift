//
//  GameBoy.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

/// The class that ties all of the Game Boy's components together into a cohesive whole.
/// Instantiate and start with a game ROM.
class GameBoy: ObservableObject {
    /// T cycles per frame: 154 scanlines of 456 cycles each, which gives ~59.7 frames per second.
    static let cyclesPerFrame = 154 * 456

    let memory: GameBoyMemory
    let cpu: GameBoyCPU<GameBoyMemory>
    let ppu: GameBoyPPU<GameBoyMemory>
    let joypad = KeyboardJoypad()

    /// The last completed frame, one color (0-3) per pixel. Published once per frame, so the
    /// UI redraws 60 times per second instead of once per pixel or per instruction.
    @Published var frame: [UInt8] = Array(repeating: 0, count: displayBufferWidth * displayBufferHeight)

    init() {
        let memory = GameBoyMemory()

        self.memory = memory
        self.cpu = GameBoyCPU(addressBus: memory)
        self.ppu = GameBoyPPU(addressBus: memory)

        memory.joypad = joypad
    }

    /// Runs one CPU instruction and lets the rest of the hardware catch up by the same
    /// number of cycles. This is the heartbeat of the emulator: the CPU, PPU and timer are
    /// independent machines that only stay in sync because they count the same cycles.
    ///
    /// - Returns: Whether the PPU completed a frame, and how many cycles passed.
    @discardableResult
    func step() -> (frameCompleted: Bool, cycles: Int) {
        let tCycles = cpu.step()
        memory.tickClock(cycles: tCycles)
        return (ppu.step(cycles: tCycles), tCycles)
    }

    /// Runs the emulation until the PPU has finished drawing a frame.
    func runFrame() {
        // The cycle limit ends the frame when the game has switched the LCD off
        var cycles = 0
        while cycles < GameBoy.cyclesPerFrame {
            let result = step()
            if result.frameCompleted {
                break
            }
            cycles += result.cycles
        }
    }

    // ponytail: runs on the main actor. A frame takes well under a millisecond of host time
    // in release builds; move it to a background task if debug builds stutter.
    @MainActor
    func start(withROM data: Data) async {
        memory.loadCartridge(data: data)

        let frameDuration = Duration.seconds(Double(GameBoy.cyclesPerFrame) / GameBoyClock.frequency)
        var nextFrame = ContinuousClock.now

        // Emulate a whole frame as fast as possible, then sleep until it is due. Sleeping
        // after every instruction can't work: a sleep takes far longer than the ~1µs asked for.
        while !Task.isCancelled {
            runFrame()
            frame = ppu.displayBuffer

            nextFrame += frameDuration
            try? await Task.sleep(until: nextFrame, clock: .continuous)
        }
    }
}
