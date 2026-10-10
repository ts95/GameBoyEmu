//
//  GameBoyViewModel.swift
//  GameBoyEmu
//

import Foundation
import Observation

/// The UI's side of the emulator: the picture to show and the buttons being held.
///
/// Everything here lives on the main actor, like the views that use it. The emulation itself
/// runs on the `Emulator` actor, and the two only exchange copies of values.
@MainActor
@Observable
final class GameBoyViewModel {
    /// The last completed frame, one pixel (red, green, blue and an unused byte) per element.
    private(set) var frame: [UInt32] = Array(repeating: blankPixel, count: displayBufferWidth * displayBufferHeight)

    /// Which buttons are held down. Changes are forwarded to the emulator.
    var joypad = JoypadState() {
        didSet {
            guard joypad != oldValue else { return }
            // The whole state is sent rather than the one button that changed, so the
            // emulator always ends up with what the UI shows
            Task { [emulator, joypad] in
                await emulator.setJoypad(joypad)
            }
        }
    }

    /// Whether the sound is switched off. Changes are forwarded to the emulator.
    var isMuted = false {
        didSet {
            guard isMuted != oldValue else { return }
            Task { [emulator, isMuted] in
                await emulator.setMuted(isMuted)
            }
        }
    }

    private let emulator = Emulator()

    /// The problem to tell the player about, if any. Set back to `nil` once it has been shown.
    var error: GameBoyError?

    /// Whether the game stopped because of an error it can't continue from.
    private(set) var hasFailed = false

    /// Runs a game, updating `frame` as frames arrive, until the calling task is cancelled.
    /// Anything that goes wrong ends up in `error` rather than being thrown, because this is
    /// where errors turn into something the player sees.
    ///
    /// The first call starts the game. Later calls on the same model carry on from where the
    /// previous one was cancelled, because the emulator keeps the machine's state in memory.
    func run(_ game: Game) async {
        joypad = JoypadState() // Nothing is held when coming (back) to the game

        do {
            let rom: Data
            do {
                rom = try Data(contentsOf: game.romURL)
            } catch {
                throw GameBoyError.romNotReadable(name: game.title, reason: error.localizedDescription)
            }

            let frames = emulator.run(rom: rom, saveURL: game.saveURL) { [weak self] warning in
                Task { @MainActor in
                    self?.error = warning
                }
            }
            for try await frame in frames {
                self.frame = frame
            }
        } catch let error as GameBoyError {
            self.error = error
            hasFailed = true
        } catch {
            self.error = .unexpected(reason: error.localizedDescription)
            hasFailed = true
        }
    }
}

/// The games that have been started since the app launched.
///
/// Leaving a game doesn't end it: its model, and with it the emulator and the entire state of
/// the machine, stays here, frozen, until the player comes back. Nothing is written to disk
/// for this, so it lasts only as long as the app does. After that, the game's own save data
/// is what remains.
@MainActor
final class GameSessions {
    private var models: [Game.ID: GameBoyViewModel] = [:]

    /// The model of a game's session, starting a new one if there is none.
    func model(for game: Game) -> GameBoyViewModel {
        if let model = models[game.id] {
            return model
        }
        let model = GameBoyViewModel()
        models[game.id] = model
        return model
    }

    /// Forgets a game's session, so that it starts from the beginning next time.
    func end(_ game: Game) {
        models[game.id] = nil
    }

    /// Forgets a game's session if it stopped with an error, since it can't be continued.
    func endIfFailed(_ game: Game) {
        if models[game.id]?.hasFailed == true {
            end(game)
        }
    }
}
