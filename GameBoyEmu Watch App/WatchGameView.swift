//
//  WatchGameView.swift
//  GameBoyEmu Watch App
//

import SwiftUI

/// A game on the watch. The whole face is the screen, and the controls are the wearer:
///
/// - tilting the wrist is the d-pad
/// - double tap (thumb and index finger, twice), or a tap on the screen, is A
/// - a flick of the wrist is B
/// - turning the Digital Crown up is Start, and down is Select
struct WatchGameView: View {
    let game: Game
    let sync: WatchSync

    @State private var model = WatchGameModel()
    /// Where the Digital Crown is, and where it was at the last press it caused.
    @State private var crown = 0.0
    @State private var crownAtLastPress = 0.0
    @FocusState private var isFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

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
        Button {
            model.tap(\.aButtonPressed)
        } label: {
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func sendSave() {
        Task {
            // ponytail: the emulator writes the save a moment after the game stops, and
            // there is no telling exactly when. A second is plenty.
            try? await Task.sleep(for: .seconds(1))
            sync.sendSave(of: game)
        }
    }
}
