import Foundation
import Testing
@testable import GameBoyEmu

// MARK: - Joypad

@Test func aQuickTapIsHeldLongEnoughForTheGameToSeeIt() throws {
    var down = JoypadState()
    down.dPadState = .down

    var queue = JoypadQueue()
    #expect(queue.advanceFrame() == JoypadState()) // Nothing pressed yet

    // A tap: pressed and released again before the next frame
    queue.report(down)
    queue.report(JoypadState())

    for _ in 0..<JoypadQueue.minimumFrames {
        #expect(queue.advanceFrame() == down)
    }
    #expect(queue.advanceFrame() == JoypadState())
}

@Test func aPressAfterAPauseTakesEffectOnTheNextFrame() throws {
    var a = JoypadState()
    a.aButtonPressed = true

    var queue = JoypadQueue()
    for _ in 0..<10 { _ = queue.advanceFrame() }

    queue.report(a)
    #expect(queue.advanceFrame() == a)
}

@Test func aChangeOfDirectionByWayOfNothingHeldIsNotKeptWaiting() throws {
    var right = JoypadState(), up = JoypadState()
    right.dPadState = .right
    up.dPadState = .up

    var queue = JoypadQueue()
    queue.report(right)
    for _ in 0..<10 { _ = queue.advanceFrame() }

    // The thumb rolls from right to up, letting go in between
    queue.report(JoypadState())
    queue.report(up)
    #expect(queue.advanceFrame() == JoypadState())
    #expect(queue.advanceFrame() == up)
}

// MARK: - Emulator

@Test func emulatorDeliversFramesUntilItsConsumerStops() async throws {
    let emulator = Emulator()
    var frames = 0

    // Leaving the loop ends the stream, which is what stops the emulation
    for try await frame in emulator.run(rom: Data(count: 0x8000), saveURL: nil) {
        #expect(frame.count == displayBufferWidth * displayBufferHeight)
        frames += 1
        if frames == 3 {
            break
        }
    }

    #expect(frames == 3)
}

@Test func emulatorCarriesOnWhereItWasStopped() async throws {
    // A program that counts in register-backed RAM: INC (HL) in a loop, with HL = 0xC000
    var rom = [UInt8](repeating: 0, count: 0x8000)
    rom.replaceSubrange(0x100..<0x106, with: [0x21, 0x00, 0xC0, 0x34, 0x18, 0xFD]) // LD HL; INC (HL); JR -3

    let emulator = Emulator()
    for try await _ in emulator.run(rom: Data(rom), saveURL: nil) { break }

    // Running again must not reload the cartridge. Proof: this "ROM" isn't one, and loading
    // it would throw, but the machine already has its cartridge and simply continues.
    var frames = 0
    for try await _ in emulator.run(rom: Data(), saveURL: nil) {
        frames += 1
        if frames == 2 { break }
    }
    #expect(frames == 2)
}
