import Testing
@testable import GameBoyEmu

@Test func aStickPointsInItsStrongerDirection() {
    #expect(DPadState(x: 0.3, y: -0.3) == .idle) // Inside the dead zone
    #expect(DPadState(x: 0.9, y: 0.6) == .right)
    #expect(DPadState(x: -0.9, y: 0.6) == .left)
    #expect(DPadState(x: 0.2, y: 1) == .up)
    #expect(DPadState(x: 0.2, y: -1) == .down)
}

@Test func theNewestDirectionKeyWinsAndFallsBackWhenLetGo() {
    var keyboard = KeyboardControls()
    var joypad = JoypadState()

    _ = keyboard.handle("w", isDown: true, joypad: &joypad)
    _ = keyboard.handle("a", isDown: true, joypad: &joypad)
    #expect(joypad.dPadState == .left)
    _ = keyboard.handle("a", isDown: true, joypad: &joypad) // The key repeating
    _ = keyboard.handle("a", isDown: false, joypad: &joypad)
    #expect(joypad.dPadState == .up) // W is still down
    _ = keyboard.handle("w", isDown: false, joypad: &joypad)
    #expect(joypad.dPadState == .idle)

    #expect(!keyboard.handle("q", isDown: true, joypad: &joypad))
}
