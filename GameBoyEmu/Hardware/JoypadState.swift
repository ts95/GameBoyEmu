//
//  JoypadState.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 03/07/2024.
//

import Foundation

enum DPadState {
    case idle
    case up
    case down
    case left
    case right
}

/// Which buttons are held down right now.
///
/// A plain value rather than a shared object: the UI owns one copy on the main actor and
/// sends a new copy to the emulator whenever it changes, so the two never touch the same memory.
struct JoypadState: Equatable, Sendable {
    var dPadState = DPadState.idle
    var aButtonPressed = false
    var bButtonPressed = false
    var startButtonPressed = false
    var selectButtonPressed = false
}
