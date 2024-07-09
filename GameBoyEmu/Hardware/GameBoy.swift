//
//  GameBoy.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

class GameBoy {
    let memory: GameBoyMemory
    let cpu: GameBoyCPU<GameBoyMemory>
    let ppu: GameBoyPPU<GameBoyMemory>

    init() {
        memory = GameBoyMemory()
        cpu = GameBoyCPU(memory: memory)
        ppu = GameBoyPPU(memory: memory)
    }

    func start(withROM data: Data) async {
        memory.loadCartridge(data: data)

        while true {
            do {
                try await cpu.step()
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }
}
