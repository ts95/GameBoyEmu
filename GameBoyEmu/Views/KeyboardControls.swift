//
//  KeyboardControls.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 03/07/2024.
//

import SwiftUI

/// Keyboard controls: WASD = d-pad, J = A, K = B, Z or N = Select, X or M = Start.
struct KeyboardControls {
    /// The direction keys that are down, in the order they went down. The d-pad points
    /// one way only, so the newest wins, and letting go of it falls back to the one before.
    private var heldDirections: [DPadState] = []

    mutating func handle(_ keyPress: KeyPress, joypad: inout JoypadState) -> KeyPress.Result {
        // Lowercased, so the keys still work with Caps Lock on. A key held down repeats;
        // the repeats change nothing, but taking them keeps the system from beeping.
        guard let key = keyPress.key.character.lowercased().first,
              handle(key, isDown: keyPress.phase != .up, joypad: &joypad) else {
            return .ignored
        }
        return .handled
    }

    /// Returns whether the key is one of the controls.
    mutating func handle(_ key: Character, isDown: Bool, joypad: inout JoypadState) -> Bool {
        switch key {
        case "w": hold(.up, isDown, &joypad)
        case "s": hold(.down, isDown, &joypad)
        case "a": hold(.left, isDown, &joypad)
        case "d": hold(.right, isDown, &joypad)
        case "j": joypad.aButtonPressed = isDown
        case "k": joypad.bButtonPressed = isDown
        case "z", "n": joypad.selectButtonPressed = isDown
        case "x", "m": joypad.startButtonPressed = isDown
        default: return false
        }
        return true
    }

    private mutating func hold(_ direction: DPadState, _ isDown: Bool, _ joypad: inout JoypadState) {
        if !isDown {
            heldDirections.removeAll { $0 == direction }
        } else if !heldDirections.contains(direction) {
            heldDirections.append(direction)
        }
        joypad.dPadState = heldDirections.last ?? .idle
    }
}
