//
//  WatchGameModel.swift
//  GameBoyEmu Watch App
//

import CoreMotion
import Foundation
import Observation

/// A game running on the watch: the picture to show, and the wrist that controls it.
///
/// The watch has no room for buttons, so the d-pad is the tilt of the wrist and B is a
/// flick of it, both read from the motion sensors.
@MainActor
@Observable
final class WatchGameModel {
    /// The last completed frame, one pixel (red, green, blue and an unused byte) per element.
    private(set) var frame: [UInt32] = Array(repeating: blankPixel, count: displayBufferWidth * displayBufferHeight)

    /// The problem to tell the player about, if any.
    private(set) var error: GameBoyError?
    /// Whether the game stopped with an error, and so can't be carried on.
    private(set) var hasFailed = false

    private let emulator = Emulator()

    /// What is held down. Only the d-pad is ever held; buttons are tapped.
    private var joypad = JoypadState() {
        didSet {
            if joypad != oldValue {
                send.yield(joypad)
            }
        }
    }

    /// Every joypad state on its way to the emulator. They go through one queue so that
    /// they arrive in the order they were made: a release must never overtake its press.
    private let send: AsyncStream<JoypadState>.Continuation

    private let motion = CMMotionManager()
    private var controls = MotionControls()

    init() {
        let (states, send) = AsyncStream.makeStream(of: JoypadState.self)
        self.send = send
        Task { [emulator] in
            for await state in states {
                await emulator.setJoypad(state)
            }
        }
    }

    deinit {
        send.finish()
    }

    /// Runs a game, updating `frame` as frames arrive, until the calling task is cancelled.
    ///
    /// The first call starts the game. Later calls carry on from where the previous one was
    /// cancelled, because the emulator keeps the machine's state in memory.
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
            hasFailed = true
        } catch {
            self.error = .unexpected(reason: error.localizedDescription)
            hasFailed = true
        }
    }

    /// Presses a button and lets go of it again. The emulator holds each of the two states
    /// long enough for the game to notice.
    func tap(_ button: WritableKeyPath<JoypadState, Bool>) {
        var pressed = joypad
        pressed[keyPath: button] = true
        send.yield(pressed)
        send.yield(joypad)
    }

    // MARK: - Motion

    /// Starts reading the wrist. The way the watch is held at that moment counts as level.
    func startMotion() {
        guard motion.isDeviceMotionAvailable else {
            return
        }
        controls.recenter()
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
            guard let reading else {
                return
            }
            let gravity = reading.gravity
            let rotation = reading.rotationRate
            let rate = (rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z).squareRoot()
            let time = reading.timestamp
            // The readings were asked for on the main queue
            MainActor.assumeIsolated {
                self?.moved(gravityX: gravity.x, gravityY: gravity.y, rotationRate: rate, time: time)
            }
        }
    }

    func stopMotion() {
        motion.stopDeviceMotionUpdates()
        joypad.dPadState = .idle
    }

    /// Takes the way the watch is held right now as level.
    func recenter() {
        controls.recenter()
    }

    private func moved(gravityX: Double, gravityY: Double, rotationRate: Double, time: TimeInterval) {
        if controls.update(gravityX: gravityX, gravityY: gravityY, rotationRate: rotationRate, time: time) {
            tap(\.bButtonPressed)
        }
        joypad.dPadState = controls.dPad
    }
}
