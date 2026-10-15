//
//  WatchGameView.swift
//  GameBoyEmu Watch App
//

import SwiftUI

/// A game on the watch. The whole face is the screen, and the controls are the wearer:
///
/// - tilting the wrist is the d-pad
/// - a touch on the right half of the screen, or double tap (thumb and index finger,
///   twice), is A
/// - a touch on the left half of the screen, or a flick of the wrist, is B
/// - turning the Digital Crown up is Start, and down is Select
struct WatchGameView: View {
    /// The game's session, which the library keeps so that the game carries on from where it
    /// was left.
    let model: WatchGameModel
    let game: Game
    let sync: WatchSync

    /// Where the Digital Crown is, and where it was at the last press it caused.
    @State private var crown = 0.0
    @State private var crownAtLastPress = 0.0
    @FocusState private var isFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// The button last pressed on the screen, shown over its half until a moment after the
    /// finger lifts.
    @State private var shownButton: ScreenButton?
    @State private var isTouching = false
    /// Counts presses, so that hiding an earlier one doesn't hide a later one.
    @State private var presses = 0

    /// The color of A and B on iPhone, as it is in dark mode, which the watch always is.
    private let buttonColor = Color(red: 255/255, green: 55/255, blue: 95/255)

    private enum ScreenButton {
        case a, b
    }

    /// The current frame as a 160x144 image, scaled up without smoothing.
    @ViewBuilder
    var screen: some View {
        let pixels = model.frame.withUnsafeBufferPointer { Data(buffer: $0) }

        if let provider = CGDataProvider(data: pixels as CFData),
           let image = CGImage(width: displayBufferWidth,
                               height: displayBufferHeight,
                               bitsPerComponent: 8,
                               bitsPerPixel: 32,
                               bytesPerRow: displayBufferWidth * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    var body: some View {
        // Touches on the screen go to the gesture below, so the button itself is only ever
        // pressed by double tap
        Button {
            press(.a)
            hideShownButton()
        } label: {
            GeometryReader { proxy in
                screen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .overlay(alignment: shownButton == .b ? .leading : .trailing) {
                        if let shownButton {
                            buttonColor.opacity(0.35)
                                .frame(width: proxy.size.width / 2)
                                .overlay {
                                    Text(shownButton == .a ? "A" : "B")
                                        .font(.title.bold())
                                        .foregroundStyle(.white)
                                }
                                .allowsHitTesting(false)
                        }
                    }
                    // Pressed as the finger comes down, not when it lifts, to lose no time
                    .highPriorityGesture(DragGesture(minimumDistance: 0)
                        .onChanged { touch in
                            guard !isTouching else {
                                return
                            }
                            isTouching = true
                            press(touch.startLocation.x < proxy.size.width / 2 ? .b : .a)
                        }
                        .onEnded { _ in
                            isTouching = false
                            hideShownButton()
                        })
            }
        }
        .buttonStyle(NoPressFeedback())
        // The system's double tap gesture presses the button, like a tap on it does
        .handGestureShortcut(.primaryAction)
        .focusable()
        .focused($isFocused)
        .digitalCrownRotation($crown, from: -1000, through: 1000, by: 1, sensitivity: .low, isContinuous: true)
        .onChange(of: crown) { _, crown in
            // One press per notch, however far the crown is spun
            guard abs(crown - crownAtLastPress) >= 1 else {
                return
            }
            model.tap(crown > crownAtLastPress ? \.startButtonPressed : \.selectButtonPressed)
            crownAtLastPress = crown
        }
        .overlay {
            if let error = model.error {
                Text(error.errorDescription ?? "")
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Recenter", systemImage: "scope") {
                    model.recenter()
                }
            }
        }
        .task {
            isFocused = true
            model.startMotion()
            await model.run(game)
        }
        .onDisappear {
            model.stopMotion()
            sendSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                sendSave() // The wrist went down, and the game may never be left properly
            }
        }
    }

    /// Shows the label as it is, pressed or not. The screen is the A button, and dimming or
    /// shrinking it on every press would only get in the way of the game.
    private struct NoPressFeedback: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }

    private func press(_ button: ScreenButton) {
        model.tap(button == .a ? \.aButtonPressed : \.bButtonPressed)
        shownButton = button
        presses += 1
    }

    private func hideShownButton() {
        let press = presses
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            if press == presses {
                shownButton = nil
            }
        }
    }

    private func sendSave() {
        Task {
            // ponytail: the emulator writes the save a moment after the game stops, and
            // there is no telling exactly when. A second is plenty.
            try? await Task.sleep(for: .seconds(1))
            sync.sendSave(of: game)
        }
    }
}
