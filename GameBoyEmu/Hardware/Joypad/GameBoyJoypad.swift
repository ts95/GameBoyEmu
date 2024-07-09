//
//  GameBoyJoypad.swift
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

protocol GameBoyJoypad: AnyObject {
    var dPadState: DPadState { get set }
    var aButtonPressed: Bool { get set }
    var bButtonPressed: Bool { get set }
    var startButtonPressed: Bool { get set }
    var selectButtonPressed: Bool { get set }
}
