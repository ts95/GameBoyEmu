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

    /// Runs a game, updating `frame` as frames arrive, until the calling task is cancelled.
    /// Anything that goes wrong ends up in `error` rather than being thrown, because this is
    /// where errors turn into something the player sees.
    func run(_ game: Game) async {
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
        } catch {
            self.error = .unexpected(reason: error.localizedDescription)
        }
    }
}
