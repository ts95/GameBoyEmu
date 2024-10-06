//
//  GameBoyClock.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

class GameBoyClock: ClockProtocol {
    /// The clock frequency of the Game Boy, approximately 4.19 MHz.
    static let frequency: Double = 4194304.0

    /// Total number of clock cycles since the start of emulation.
    private(set) var totalCycles: UInt64 = 0

    /// Advances the clock by the given number of cycles.
    ///
    /// - Parameter cycles: The number of cycles to advance the clock.
    func tick(cycles: Int) async throws {
        totalCycles &+= UInt64(cycles) // Increment and wrap around on overflow

        let nanosecondsPerCycle = 1_000_000_000.0 / GameBoyClock.frequency
        let sleepDuration = UInt64(Double(cycles) * nanosecondsPerCycle)

        try await Task.sleep(nanoseconds: sleepDuration)
    }

    /// Resets the clock to zero.
    func reset() {
        totalCycles = 0
    }
}

protocol ClockProtocol {
    /// Advances the clock by the given number of cycles and sleeps for the duration of those cycles.
    ///
    /// - Parameter cycles: The number of clock cycles (TCycles) to advance the clock.
    func tick(cycles: Int) async throws

    /// Resets the clock to zero.
    func reset()

    /// The total number of clock cycles since the start of emulation.
    var totalCycles: UInt64 { get }
}
