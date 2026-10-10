//
//  GameBoyClock.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

/// The Game Boy's timer hardware: the DIV, TIMA, TMA and TAC registers at 0xFF04-0xFF07.
///
/// Time inside the emulator is counted in T cycles, not in real seconds. Every component is
/// advanced by the number of cycles the CPU just spent, and only the outer run loop cares
/// about how long a frame takes on the host machine.
class GameBoyClock {
    /// The clock frequency of the Game Boy, approximately 4.19 MHz.
    static let frequency: Double = 4194304.0

    /// A free-running 16-bit counter that goes up by one every T cycle.
    /// The DIV register is simply its upper 8 bits.
    private(set) var counter: UInt16 = 0xABCC

    /// TIMA: the configurable counter. Requests the timer interrupt when it overflows.
    var tima: UInt8 = 0
    /// TMA: the value TIMA restarts from after overflowing.
    var tma: UInt8 = 0
    /// TAC: bit 2 turns TIMA on, bits 0-1 select its speed.
    var tac: UInt8 = 0

    /// TIMA counts up each time this bit of `counter` goes from 1 to 0.
    private var timaBit: UInt16 {
        switch tac & 0x03 {
        case 0: return 1 << 9  // Every 1024 cycles
        case 1: return 1 << 3  // Every 16 cycles
        case 2: return 1 << 5  // Every 64 cycles
        default: return 1 << 7 // Every 256 cycles
        }
    }

    /// Advances the clock by the given number of cycles.
    ///
    /// - Parameter cycles: The number of cycles to advance the clock.
    /// - Returns: Whether TIMA overflowed, meaning the timer interrupt should be requested.
    func tick(cycles: Int) -> Bool {
        var overflowed = false

        for _ in 0..<cycles {
            let previous = counter
            counter &+= 1

            if tac & 0x04 != 0, previous & timaBit != 0, counter & timaBit == 0 {
                tima &+= 1
                if tima == 0 {
                    tima = tma
                    overflowed = true
                }
            }
        }

        return overflowed
    }

    /// Register access, by address.
    subscript(address: Int) -> UInt8 {
        get {
            switch address {
            case 0xFF04: return UInt8(counter >> 8)
            case 0xFF05: return tima
            case 0xFF06: return tma
            default: return tac | 0xF8
            }
        }
        set {
            switch address {
            case 0xFF04: counter = 0 // Writing anything to DIV resets it
            case 0xFF05: tima = newValue
            case 0xFF06: tma = newValue
            default: tac = newValue & 0x07
            }
        }
    }
}
