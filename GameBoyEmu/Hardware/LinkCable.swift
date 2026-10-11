//
//  LinkCable.swift
//  GameBoyEmu
//

import Foundation

/// Two Game Boys joined by a link cable, in the same process.
///
/// The cable itself is just each serial port handing its messages to the other. The harder part of
/// linking is time: a transfer only works if both consoles are at the same moment when it
/// happens. So the two are advanced together, a single instruction at a time, always
/// stepping the one that is behind.
final class LinkCable {
    let first: GameBoy
    let second: GameBoy

    /// How far ahead of the second console the first one is, in cycles.
    private var lead = 0

    init(_ first: GameBoy, _ second: GameBoy) {
        self.first = first
        self.second = second

        first.memory.serial.cable = { [weak port = second.memory.serial] in port?.receive($0) }
        second.memory.serial.cable = { [weak port = first.memory.serial] in port?.receive($0) }
    }

    deinit {
        first.memory.serial.cable = nil
        second.memory.serial.cable = nil
    }

    /// Advances both consoles by the given number of cycles, keeping them within one
    /// instruction of each other.
    func run(cycles: Int) throws {
        var remainingFirst = cycles
        var remainingSecond = cycles

        while remainingFirst > 0 || remainingSecond > 0 {
            if remainingSecond <= 0 || (remainingFirst > 0 && lead <= 0) {
                let elapsed = try first.step().cycles
                remainingFirst -= elapsed
                lead += elapsed
            } else {
                let elapsed = try second.step().cycles
                remainingSecond -= elapsed
                lead -= elapsed
            }
        }
    }
}
