import Foundation
import Testing
@testable import GameBoyEmu

@Test func tiltingPressesTheDirectionTheWatchLeansIn() {
    var controls = MotionControls()
    // The first reading is what level means, however the watch is held
    _ = controls.update(gravityX: 0.1, gravityY: -0.5, rotationRate: 0, time: 0)
    #expect(controls.dPad == .idle)

    _ = controls.update(gravityX: 0.5, gravityY: -0.5, rotationRate: 0, time: 0.1)
    #expect(controls.dPad == .right)
    _ = controls.update(gravityX: -0.3, gravityY: -0.5, rotationRate: 0, time: 0.2)
    #expect(controls.dPad == .left)
    _ = controls.update(gravityX: 0.1, gravityY: -0.1, rotationRate: 0, time: 0.3)
    #expect(controls.dPad == .up)
    _ = controls.update(gravityX: 0.1, gravityY: -0.9, rotationRate: 0, time: 0.4)
    #expect(controls.dPad == .down)
}

@Test func aPressedDirectionHoldsUntilTheWatchIsNearlyLevelAgain() {
    var controls = MotionControls()
    _ = controls.update(gravityX: 0, gravityY: 0, rotationRate: 0, time: 0)

    _ = controls.update(gravityX: 0.2, gravityY: 0, rotationRate: 0, time: 0.1)
    #expect(controls.dPad == .idle) // Not far enough to press

    _ = controls.update(gravityX: 0.3, gravityY: 0, rotationRate: 0, time: 0.2)
    _ = controls.update(gravityX: 0.2, gravityY: 0, rotationRate: 0, time: 0.3)
    #expect(controls.dPad == .right) // But far enough to keep holding

    _ = controls.update(gravityX: 0.1, gravityY: 0, rotationRate: 0, time: 0.4)
    #expect(controls.dPad == .idle)
}

@Test func aFlickIsReportedOnceAndLeavesTheDPadAlone() {
    var controls = MotionControls()
    _ = controls.update(gravityX: 0, gravityY: 0, rotationRate: 0, time: 0)

    let first = controls.update(gravityX: 0, gravityY: 0, rotationRate: 8, time: 1)
    // The rest of the same flick, with the watch swinging through a steep tilt
    let rest = controls.update(gravityX: 0.8, gravityY: 0, rotationRate: 8, time: 1.2)
    #expect(first)
    #expect(!rest)
    #expect(controls.dPad == .idle)

    let second = controls.update(gravityX: 0, gravityY: 0, rotationRate: 8, time: 2)
    #expect(second)
}

@Test func recenteringTakesTheCurrentTiltAsLevel() {
    var controls = MotionControls()
    _ = controls.update(gravityX: 0, gravityY: 0, rotationRate: 0, time: 0)
    _ = controls.update(gravityX: 0.5, gravityY: 0, rotationRate: 0, time: 0.1)
    #expect(controls.dPad == .right)

    controls.recenter()
    _ = controls.update(gravityX: 0.5, gravityY: 0, rotationRate: 0, time: 0.2)
    #expect(controls.dPad == .idle)
}
