//
//  GameBoySerialPort.swift
//  GameBoyEmu
//

import Foundation

/// The Game Boy's serial port, which the link cable plugs into: the SB and SC registers
/// at 0xFF01 and 0xFF02.
///
/// A transfer swaps one byte with the console at the other end of the cable. Both consoles
/// put the byte they want to send in SB, and one of them provides the clock: on each of its
/// eight ticks, both shift one bit out and one bit in. Afterwards each has the other's byte
/// in SB and gets a serial interrupt.
///
/// Which console provides the clock is decided by the games. The other one sets up its
/// transfer and waits, for as long as it takes, for the clock to arrive.
///
/// ponytail: transfers happen a byte at a time rather than a bit at a time. Shift bit by bit
/// if a game is found that looks at SB halfway through a transfer.
final class GameBoySerialPort {
    /// SB: the byte to send, which becomes the byte received when the transfer is over.
    var data: UInt8 = 0

    /// SC. Bit 7: a transfer has been asked for and isn't finished. Bit 0: this console
    /// provides the clock. Bit 1 (Game Boy Color): use the fast clock.
    var control: UInt8 = 0 {
        didSet {
            if isTransferring && isClockSource {
                cyclesRemaining = control & 0x02 != 0 ? 128 : 4096 // 8 bits at 262144 or 8192 Hz
            }
        }
    }

    /// The serial port at the other end of the link cable, if one is plugged in.
    weak var partner: GameBoySerialPort?

    private var cyclesRemaining = 0
    /// Set when the console at the other end has completed a transfer with this one.
    private var hasReceivedFromPartner = false

    private var isTransferring: Bool { control & 0x80 != 0 }
    private var isClockSource: Bool { control & 0x01 != 0 }

    /// Advances the port by the given number of cycles.
    ///
    /// - Returns: Whether a transfer finished, meaning the serial interrupt should be requested.
    func tick(cycles: Int) -> Bool {
        if hasReceivedFromPartner {
            hasReceivedFromPartner = false
            return true
        }

        guard isTransferring && isClockSource else {
            return false // Idle, or waiting for the other console's clock
        }

        cyclesRemaining -= cycles
        guard cyclesRemaining <= 0 else {
            return false
        }

        // With nothing at the other end, the input line reads as all ones
        data = partner?.exchange(data) ?? 0xFF
        control &= 0x7F
        return true
    }

    /// Takes part in a transfer clocked by the console at the other end.
    ///
    /// - Parameter incoming: The byte the other console sends.
    /// - Returns: The byte this console sends back.
    private func exchange(_ incoming: UInt8) -> UInt8 {
        // ponytail: a console that hasn't set up a transfer is treated as not being there.
        // On hardware its shift register still moves with the incoming clock.
        guard isTransferring && !isClockSource else {
            return 0xFF
        }

        let outgoing = data
        data = incoming
        control &= 0x7F
        hasReceivedFromPartner = true
        return outgoing
    }
}
