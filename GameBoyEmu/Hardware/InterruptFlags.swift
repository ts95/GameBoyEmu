//
//  InterruptFlags.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

struct InterruptFlags {
    var vBlank = false
    var lcdStat = false
    var timer = false
    var serial = false
    var joypad = false

    init(from byte: UInt8) {
        vBlank = (byte & 0b1) == 0b1
        lcdStat = (byte & 0b10) == 0b10
        timer = (byte & 0b100) == 0b100
        serial = (byte & 0b1000) == 0b1000
        joypad = (byte & 0b10000) == 0b10000
    }

    subscript(_ keyPath: KeyPath<InterruptFlags, Bool>) -> UInt8 {
        self[keyPath: keyPath] ? 1 : 0
    }

    var byte: UInt8 {
        0b11100000 |
        self[\.joypad] << 4 |
        self[\.serial] << 3 |
        self[\.timer] << 2 |
        self[\.lcdStat] << 1 |
        self[\.vBlank]
    }
}
