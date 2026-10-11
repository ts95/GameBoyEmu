//
//  JoypadState+Controller.swift
//  GameBoyEmu
//

import GameController

extension JoypadState {
    /// What a game controller is holding down right now.
    ///
    /// A and B are the buttons with those letters on them, which sit the other way round on
    /// an Xbox controller than on a Nintendo one. On a controller without letters, they go
    /// by where they sit on a Game Boy: the right-hand one is A and the bottom one is B.
    /// Menu is Start and Options is Select. The d-pad and the left stick both steer.
    init(_ pad: GCExtendedGamepad) {
        let stick = DPadState(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
        dPadState = stick == .idle ? DPadState(x: pad.dpad.xAxis.value, y: pad.dpad.yAxis.value) : stick
        // The system names the buttons by where they sit: `buttonA` is the bottom one and
        // `buttonB` the right-hand one. Its symbol tells what is printed on it.
        let bottomIsLabelledA = pad.buttonA.sfSymbolsName?.hasPrefix("a.") ?? false
        aButtonPressed = (bottomIsLabelledA ? pad.buttonA : pad.buttonB).isPressed
        bButtonPressed = (bottomIsLabelledA ? pad.buttonB : pad.buttonA).isPressed
        startButtonPressed = pad.buttonMenu.isPressed
        selectButtonPressed = pad.buttonOptions?.isPressed ?? false
    }

    /// What the Apple TV remote is holding down right now. It has too few buttons for a
    /// Game Boy: the clickpad is the d-pad and, clicked, A; Play/Pause is B. Start and
    /// Select are in the menu the Back button brings up.
    init(remote: GCMicroGamepad) {
        dPadState = DPadState(x: remote.dpad.xAxis.value, y: remote.dpad.yAxis.value)
        aButtonPressed = remote.buttonA.isPressed
        bButtonPressed = remote.buttonX.isPressed
    }
}

extension DPadState {
    /// The one direction a stick or d-pad points in, with right and up positive.
    /// A Game Boy d-pad has no diagonals to speak of, so the stronger axis wins.
    init(x: Float, y: Float) {
        if max(abs(x), abs(y)) < 0.5 {
            self = .idle
        } else if abs(x) > abs(y) {
            self = x > 0 ? .right : .left
        } else {
            self = y > 0 ? .up : .down
        }
    }
}
