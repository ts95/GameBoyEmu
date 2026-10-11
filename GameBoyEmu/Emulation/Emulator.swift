//
//  Emulator.swift
//  GameBoyEmu
//

import Foundation

/// Runs a `GameBoy` in real time, off the main thread.
///
/// The machine's state (CPU, memory, PPU, APU) is plain mutable classes with no locking. Being
/// an actor is what makes that safe: only one piece of code at a time can be inside the actor,
/// so nothing outside it can touch the machine while a frame is being emulated. The rest of
/// the app talks to it in two ways, both of which only ever pass copies of values:
///
/// - frames come out through an `AsyncStream`
/// - button presses go in through `setJoypad(_:)`
/// - link cable traffic goes in through `receiveFromCable(_:)` and out through the closure
///   given to `plugInCable(_:)`
actor Emulator {
    private let gameBoy = GameBoy()
    /// Whether the machine already has its cartridge in, from an earlier call to `run`.
    private var isCartridgeLoaded = false
    private var joypadQueue = JoypadQueue()
    private var isMuted = false

    /// Updates which buttons are held down. Takes effect at a frame boundary, when the
    /// emulation loop is suspended and the actor is free to run this.
    func setJoypad(_ state: JoypadState) {
        joypadQueue.report(state)
    }

    /// Mutes or unmutes the sound. Muting shuts the audio engine down altogether, and
    /// unmuting starts a new one; both happen at the next frame boundary.
    func setMuted(_ isMuted: Bool) {
        self.isMuted = isMuted
    }

    /// Plugs a link cable into the serial port. `send` carries each message the game sends
    /// to the console at the other end, whose messages come back through `receiveFromCable(_:)`.
    func plugInCable(_ send: @escaping @Sendable (LinkMessage) -> Void) {
        gameBoy.memory.serial.cable = send
    }

    func unplugCable() {
        gameBoy.memory.serial.cable = nil
    }

    /// Hands the serial port a message from the other console. Like everything else coming
    /// in from outside, it lands between frames.
    func receiveFromCable(_ message: LinkMessage) {
        gameBoy.memory.serial.receive(message)
    }

    /// Starts the emulation and returns its frames, one array of pixels per frame.
    ///
    /// The emulation runs for as long as someone is reading the stream. When the reader stops,
    /// for example because its task was cancelled, the stream ends and the emulation with it.
    ///
    /// Stopping only freezes the machine: everything about it stays in memory, exactly as it
    /// was, for as long as this emulator exists. Calling `run` again carries on from that
    /// point instead of starting the game over, and ignores `rom`.
    /// If the emulation can't start or can't go on, the stream ends by throwing a `GameBoyError`.
    ///
    /// - Parameters:
    ///   - rom: The cartridge ROM.
    ///   - saveURL: Where the cartridge's battery-backed RAM is kept between sessions.
    ///   - onWarning: Called for problems the game can keep running through, such as
    ///     having no sound or not being able to write the save file.
    nonisolated func run(
        rom: Data,
        saveURL: URL?,
        onWarning: @escaping @Sendable (GameBoyError) -> Void = { _ in }
    ) -> AsyncThrowingStream<[UInt32], any Error> {
        // Only the newest frame is kept: if the UI falls behind it skips frames instead of
        // slowing the emulation (and the audio) down
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    try await emulate(rom: rom, saveURL: saveURL, frames: continuation, onWarning: onWarning)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func emulate(
        rom: Data,
        saveURL: URL?,
        frames: AsyncThrowingStream<[UInt32], any Error>.Continuation,
        onWarning: @Sendable (GameBoyError) -> Void
    ) async throws {
        if !isCartridgeLoaded {
            try gameBoy.loadCartridge(data: rom, save: readSave(from: saveURL))
            isCartridgeLoaded = true
        }
        // Whatever was held down when the machine was last frozen isn't held any more
        joypadQueue = JoypadQueue()

        // The audio engine only exists while there is sound to play
        var audio: AudioOutput?
        var hasAudioFailed = false

        let frameDuration = Duration.seconds(Double(GameBoy.cyclesPerFrame) / GameBoyClock.frequency)
        var nextFrame = ContinuousClock.now
        var framesUntilSaveCheck = 60
        var hasReportedSaveFailure = false

        // Emulate a whole frame as fast as possible, then sleep until it is due. Sleeping
        // after every instruction can't work: a sleep takes far longer than the ~1µs asked for.
        while !Task.isCancelled {
            gameBoy.memory.joypad = joypadQueue.advanceFrame()
            try gameBoy.runFrame()
            frames.yield(gameBoy.ppu.displayBuffer)

            if isMuted {
                // Dropping the output stops its engine. The APU itself keeps running, because
                // games read its registers, but its samples are thrown away.
                audio = nil
                hasAudioFailed = false
            } else if audio == nil && !hasAudioFailed {
                do {
                    audio = try AudioOutput()
                } catch {
                    // No sound is not a reason to stop playing. Unmuting tries again.
                    hasAudioFailed = true
                    onWarning(.audioUnavailable(reason: error.localizedDescription))
                }
            }
            audio?.play(samples: gameBoy.memory.apu.pendingSamples)
            gameBoy.memory.apu.pendingSamples.removeAll(keepingCapacity: true)

            // A save file is just a copy of the cartridge RAM. Checking once per second
            // writes it shortly after the game has saved, without writing on every byte.
            framesUntilSaveCheck -= 1
            if framesUntilSaveCheck == 0 {
                framesUntilSaveCheck = 60
                if let saveURL, gameBoy.memory.hasBattery, gameBoy.memory.hasUnsavedExternalRam {
                    do {
                        try writeSave(to: saveURL)
                        hasReportedSaveFailure = false
                    } catch {
                        // The game keeps running and the write is retried every second,
                        // but the player is only told once per run of failures
                        if !hasReportedSaveFailure {
                            hasReportedSaveFailure = true
                            onWarning(.saveNotWritten(reason: error.localizedDescription))
                        }
                    }
                }
            }

            nextFrame += frameDuration
            if nextFrame < .now - .milliseconds(100) {
                nextFrame = .now // After a long stall, carry on from here instead of fast-forwarding
            }
            try? await Task.sleep(until: nextFrame, clock: .continuous)
        }

        // Leaving the game: don't lose what was saved in the last second
        if let saveURL, gameBoy.memory.hasBattery, gameBoy.memory.hasUnsavedExternalRam {
            try? writeSave(to: saveURL)
        }
    }

    /// Reads the save file, if there is one.
    ///
    /// A missing file just means the game hasn't been saved yet. A file that exists but
    /// can't be read is an error: starting anyway would overwrite it with an empty save.
    private func readSave(from url: URL?) throws -> Data? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw GameBoyError.saveNotReadable(reason: error.localizedDescription)
        }
    }

    private func writeSave(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic, so a crash mid-write can't leave a half-written save behind
        try Data(gameBoy.memory.externalRam).write(to: url, options: .atomic)
        gameBoy.memory.hasUnsavedExternalRam = false
    }
}

/// Makes sure every button press lasts long enough for a game to notice it.
///
/// A game only looks at the buttons once per frame, and some only every few frames. A real
/// button takes a while to press and release, but a tap on a touch screen can be over within
/// a frame or two and be missed entirely. So each state the UI reports is shown to the game
/// for a minimum number of frames before the next one replaces it.
struct JoypadQueue {
    /// About 67 ms. Pokémon Crystal's menus miss presses shorter than 3 frames.
    static let minimumFrames = 4

    /// The state the game currently sees.
    private(set) var current = JoypadState()
    private var pending: [JoypadState] = []
    private var framesShown = JoypadQueue.minimumFrames

    /// Records a new state from the UI, to be shown once the ones before it have had their turn.
    mutating func report(_ state: JoypadState) {
        pending.append(state)
    }

    /// Called once per frame. Returns the state the game should see during that frame.
    mutating func advanceFrame() -> JoypadState {
        if framesShown >= JoypadQueue.minimumFrames, !pending.isEmpty {
            current = pending.removeFirst()
            framesShown = 0
        }
        framesShown += 1
        return current
    }
}
