//
//  MotionControls.swift
//  GameBoyEmu
//

import Foundation

/// Turns the motion of a wrist into joypad input, for playing on a watch.
///
/// Tilting the watch works the d-pad, the way tilting a board steers a marble. A quick
/// flick of the wrist is a button press.
///
/// It knows nothing about sensors: it is handed readings and keeps only what it needs to
/// tell one reading from the next.
struct MotionControls {
    /// How far the watch must tilt before a direction is pressed, as the change in the pull
    /// of gravity along the screen (0.18 is about 10 degrees).
    static let pressTilt = 0.18
    /// A pressed direction lets go below this. Being lower than `pressTilt`, a wrist held
    /// right at the edge doesn't make the direction flicker.
    static let releaseTilt = 0.1
    /// How fast the wrist must turn to count as a flick, in radians per second. Steering
    /// by tilting stays well under this, and so does turning the wrist on the way somewhere.
    static let flickRate = 9.0
    /// How long a flick takes to play out, in seconds.
    static let flickDuration = 0.5

    /// The direction the tilt is holding down.
    private(set) var dPad = DPadState.idle

    /// The tilt that counts as holding the watch level: wherever it was at the first reading.
    private var neutral: (x: Double, y: Double)?
    private var lastFlick = -Double.infinity

    /// Takes the way the watch is held right now as level.
    mutating func recenter() {
        neutral = nil
        dPad = .idle
    }

    /// Takes a reading from the motion sensors.
    ///
    /// - Parameters:
    ///   - gravityX: The pull of gravity towards the right edge of the screen, from -1 to 1.
    ///   - gravityY: The pull of gravity towards the top edge of the screen, from -1 to 1.
    ///   - rotationRate: How fast the watch is turning, around any axis, in radians per second.
    ///   - time: When the reading was taken, in seconds.
    /// - Returns: Whether the wrist was just flicked.
    mutating func update(gravityX: Double, gravityY: Double, rotationRate: Double, time: TimeInterval) -> Bool {
        if time - lastFlick < Self.flickDuration {
            return false // Still the same flick, which also throws the tilt about
        }
        if rotationRate > Self.flickRate {
            lastFlick = time
            return true
        }

        let neutral = neutral ?? (gravityX, gravityY)
        self.neutral = neutral
        let x = gravityX - neutral.x
        let y = gravityY - neutral.y

        if max(abs(x), abs(y)) < (dPad == .idle ? Self.pressTilt : Self.releaseTilt) {
            dPad = .idle
        } else if abs(x) > abs(y) {
            dPad = x > 0 ? .right : .left // The right edge dips: gravity pulls that way
        } else {
            dPad = y > 0 ? .up : .down // The top edge dips, as when pushing a stick forward
        }
        return false
    }
}
