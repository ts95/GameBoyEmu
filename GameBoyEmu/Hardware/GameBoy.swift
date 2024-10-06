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
    let clock: GameBoyClock
    var memory: GameBoyMemory
    @Published var cpu: GameBoyCPU<GameBoyMemory>
    @Published var ppu: GameBoyPPU<GameBoyMemory>

    init() {
        let clock = GameBoyClock()
        let memory = GameBoyMemory()
        let cpu = GameBoyCPU(addressBus: memory)
        let ppu = GameBoyPPU(addressBus: memory)

        self.clock = clock
        self.memory = memory
        self.cpu = cpu
        self.ppu = ppu
    }

    func start(withROM data: Data) async {
        memory.loadCartridge(data: data)

        while true {
            do {
                if cpu.isClockHalted || cpu.isClockStopped {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    cpu.isClockStopped = false
                    continue
                }

                let tCycles = cpu.step()
                ppu.step(cycles: tCycles)
                try await clock.tick(cycles: tCycles)
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }
}
