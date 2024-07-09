//
//  KeyboardJoypad.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 03/07/2024.
//

import Foundation
import SwiftUI

class KeyboardJoypad: GameBoyJoypad {
    var dPadState = DPadState.idle
    var aButtonPressed = false
    var bButtonPressed = false
    var startButtonPressed = false
    var selectButtonPressed = false

    func onKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .init("w"):
            dPadState = keyPress.phase == .down ? .up : .idle
            return .handled
        case .init("s"):
            dPadState = keyPress.phase == .down ? .down : .idle
            return .handled
        case .init("a"):
            dPadState = keyPress.phase == .down ? .left : .idle
            return .handled
        case .init("d"):
            dPadState = keyPress.phase == .down ? .right : .idle
            return .handled
        case .init("j"):
            aButtonPressed = keyPress.phase == .down
            return .handled
        case .init("k"):
            bButtonPressed = keyPress.phase == .down
            return .handled
        case .init("z"):
            selectButtonPressed = keyPress.phase == .down
            return .handled
        case .init("x"):
            startButtonPressed = keyPress.phase == .down
            return .handled
        default:
            return .ignored
        }
    }
}
