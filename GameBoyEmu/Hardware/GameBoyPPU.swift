//
//  GameBoyPPU.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 03/07/2024.
//

import Foundation

class GameBoyPPU<Memory: MemoryAddressInterface> {

    let memory: Memory

    init(memory: Memory) {
        self.memory = memory
    }
}
