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
                // ponytail: the answer to a transfer the game gave up on would be taken for
                // the answer to this one. Number the messages if a game restarts transfers.
                isAwaitingReply = false
            }
        }
    }

    /// The link cable: carries a message to the console at the other end, whose answers
    /// come back through `receive(_:)`. Nil when nothing is plugged in.
    ///
    /// The other end may be in the same process or on another device, so an answer can
    /// take any amount of time to arrive.
    var cable: ((LinkMessage) -> Void)? {
        didSet {
            if isAwaitingReply {
                finish(receiving: 0xFF) // The answer is never going to come down the old cable
            }
        }
    }

    private var cyclesRemaining = 0
    /// Set once this console has clocked its byte out, until the other one's byte comes back.
    /// On hardware that takes no time at all. Here the transfer is held open instead, which
    /// to the game looks like a slow cable.
    private var isAwaitingReply = false
    private var hasFinishedTransfer = false

    private var isTransferring: Bool { control & 0x80 != 0 }
    private var isClockSource: Bool { control & 0x01 != 0 }

    /// Advances the port by the given number of cycles.
    ///
    /// - Returns: Whether a transfer finished, meaning the serial interrupt should be requested.
    func tick(cycles: Int) -> Bool {
        // Otherwise idle, or waiting for the other console: for its clock or for its answer
        if isTransferring && isClockSource && !isAwaitingReply {
            cyclesRemaining -= cycles
            if cyclesRemaining <= 0 {
                if let cable {
                    isAwaitingReply = true
                    cable(.clock(data))
                } else {
                    finish(receiving: 0xFF) // With nothing at the other end, the input line reads as all ones
                }
            }
        }

        defer { hasFinishedTransfer = false }
        return hasFinishedTransfer
    }

    /// Takes a message that has come down the cable from the other console.
    func receive(_ message: LinkMessage) {
        switch message {
        case .clock(let incoming):
            // ponytail: a console that hasn't set up a transfer is treated as not being there.
            // On hardware its shift register still moves with the incoming clock.
            guard isTransferring && !isClockSource else {
                cable?(.reply(0xFF))
                return
            }
            let outgoing = data
            finish(receiving: incoming)
            cable?(.reply(outgoing))

        case .reply(let incoming):
            if isAwaitingReply {
                finish(receiving: incoming)
            }
        }
    }

    private func finish(receiving byte: UInt8) {
        data = byte
        control &= 0x7F
        isAwaitingReply = false
        hasFinishedTransfer = true
    }
}

/// What travels along a link cable.
enum LinkMessage: Equatable, Sendable {
    /// The console providing the clock has shifted this byte out.
    case clock(UInt8)
    /// The other console's answer: the byte it shifted out in return.
    case reply(UInt8)
}
