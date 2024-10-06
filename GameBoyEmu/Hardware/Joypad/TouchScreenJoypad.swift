//
//  TouchScreenJoypad.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

class TouchScreenJoypad: GameBoyJoypad, ObservableObject {
    @Published var dPadState = DPadState.idle
    @Published var aButtonPressed = false
    @Published var bButtonPressed = false
    @Published var startButtonPressed = false
    @Published var selectButtonPressed = false
}
