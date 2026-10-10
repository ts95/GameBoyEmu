//
//  GameBoyView.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 23/06/2024.
//

import SwiftUI
import SwiftData

struct GameBoyView: View {
    /// The game's session. It is owned by whoever shows this view, so that it can outlive it.
    let model: GameBoyViewModel

    /// The game to run. `nil` shows the console switched off.
    var game: Game?

    @FocusState private var isFocused: Bool
    @GestureState private var dPadState = DPadState.idle

    /// Compact when there is little height to work with, as on a phone held sideways.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    let dPadSize: CGFloat = 150
    /// How far Select and Start stay off the bottom edge in landscape.
    let landscapeOptionButtonInset: CGFloat = 16

    let gameBoyBeige = Color(red: 182/255, green: 183/255, blue: 178/255)
    let powerLightRed = Color(red: 214/255, green: 52/255, blue: 60/255)

    var aspectRatio: CGFloat {
        CGFloat(displayBufferWidth) / CGFloat(displayBufferHeight)
    }

    /// The LCD inside its bezel, with the power light. Games draw right up to the edge of
    /// the picture because on the console a bezel was always there.
    var screen: some View {
        Rectangle()
            .fill(.white)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                canvas
            }
            // A slimmer bezel in landscape, where every point goes to the picture
            .padding(.horizontal, isLandscape ? 16 : 22)
            .padding(.vertical, isLandscape ? 10 : 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) {
                Circle()
                    .fill(powerLightRed)
                    .frame(width: 7, height: 7)
                    .padding(.leading, isLandscape ? 5 : 8)
            }
    }

    /// The current frame as a 160x144 image, scaled up without smoothing.
    @ViewBuilder
    var canvas: some View {
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
        }
    }

    var muteButton: some View {
        Button {
            model.isMuted.toggle()
        } label: {
            Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.title3)
                .frame(width: 44, height: 32)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(model.isMuted ? "Unmute" : "Mute")
    }

    var joypad: some View {
        VStack(spacing: 64) {
            HStack {
                dPad
                Spacer()
                actionButtons
            }
            .padding(.horizontal, 8)

            optionButtons
        }
    }

    /// The upright console: the screen on top and the controls below it.
    var portraitLayout: some View {
        VStack {
            screen
            muteButton
                .frame(maxWidth: .infinity, alignment: .trailing)
            Spacer()
            joypad
            Spacer()
        }
    }

    /// The console on its side: the screen in the middle, taking the full height, with the
    /// d-pad to its left and the buttons to its right. Stacking them, as in portrait, would
    /// leave no room for the screen.
    ///
    /// Select and Start go to opposite corners, under the d-pad and under A and B. Side by
    /// side they would need a column wide enough to cost the screen a good part of its size.
    var landscapeLayout: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                raised(dPad)
                selectButton
                    .padding(.bottom, landscapeOptionButtonInset)
            }

            screen

            ZStack {
                raised(actionButtons)
                VStack {
                    muteButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer()
                    startButton
                        .padding(.bottom, landscapeOptionButtonInset)
                }
            }
            .frame(width: 170)
        }
    }

    /// Places a control above the middle of its column: a third of the spare height above
    /// it and two thirds below. Thumbs rest in the upper half of a phone held sideways.
    func raised(_ control: some View) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            control
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
    }

    var dPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black)
                .frame(width: 150, height: 50)

            RoundedRectangle(cornerRadius: 8)
                .fill(.black)
                .frame(width: 50, height: 150)

            Circle()
                .fill(.white.opacity(0.2))
                .frame(width: 40, height: 40)
        }
        .frame(width: dPadSize, height: dPadSize)
        // Tilt the cross towards the pressed direction, like the real rocker
        .rotation3DEffect(.degrees(dPadState == .idle ? 0 : 12), axis: dPadTiltAxis)
        .animation(.spring(duration: 0.15), value: dPadState)
        .contentShape(Rectangle())
        // One gesture for the whole cross, so a thumb can slide from one direction to another.
        // The gesture state falls back to .idle when the finger lifts or the touch is cancelled.
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dPadState) { value, state, _ in
                    state = dPadDirection(at: value.location)
                }
        )
        .onChange(of: dPadState) { _, newState in
            model.joypad.dPadState = newState
        }
        // A faint tick for each direction pressed, including when sliding from one to the next
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.4), trigger: dPadState) { _, newState in
            newState != .idle
        }
    }

    var dPadTiltAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        switch dPadState {
        case .up, .idle: (1, 0, 0)
        case .down: (-1, 0, 0)
        case .left: (0, -1, 0)
        case .right: (0, 1, 0)
        }
    }

    func dPadDirection(at location: CGPoint) -> DPadState {
        let dx = location.x - dPadSize / 2
        let dy = location.y - dPadSize / 2

        if abs(dx) < 12 && abs(dy) < 12 {
            return .idle // The middle of the cross presses nothing
        }
        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        }
        return dy > 0 ? .down : .up
    }

    var actionButtons: some View {
        HStack(spacing: 16) {
            actionButton("B") { model.joypad.bButtonPressed = $0 }
            actionButton("A") { model.joypad.aButtonPressed = $0 }
        }
        .rotationEffect(.degrees(-20))
        .font(.title.bold())
        .foregroundStyle(.primary.opacity(0.5))
    }

    func actionButton(_ title: String, onPressChange: @escaping (Bool) -> Void) -> some View {
        Button(action: {}, label: {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 70, height: 70)
                .overlay {
                    Text(title)
                }
        })
        .buttonStyle(JoypadButtonStyle(onPressChange: onPressChange))
    }

    var optionButtons: some View {
        HStack(spacing: 16) {
            selectButton
            startButton
        }
    }

    var selectButton: some View {
        optionButton("Select") { model.joypad.selectButtonPressed = $0 }
    }

    var startButton: some View {
        optionButton("Start") { model.joypad.startButtonPressed = $0 }
    }

    func optionButton(_ title: String, onPressChange: @escaping (Bool) -> Void) -> some View {
        Button(action: {}, label: {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .fixedSize() // Never wrap a label onto two lines
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        })
        .buttonStyle(JoypadButtonStyle(onPressChange: onPressChange))
        .rotationEffect(.degrees(-5))
    }

    /// Shows the alert while the model has an error, and clears the error when it is dismissed.
    var isShowingError: Binding<Bool> {
        Binding {
            model.error != nil
        } set: { isShowing in
            if !isShowing {
                model.error = nil
            }
        }
    }

    var body: some View {
        Group {
            if isLandscape {
                // The safe area already keeps the controls clear of the screen's rounded
                // corners and the Dynamic Island, so no further side margin is added. The
                // strip above the home indicator at the bottom is used as well.
                landscapeLayout
                    .padding(.vertical, 8)
                    .ignoresSafeArea(.container, edges: .bottom)
            } else {
                portraitLayout
                    .padding()
            }
        }
        .fontDesign(.monospaced)
        .textCase(.uppercase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gameBoyBeige.opacity(0.2))
        // Keyboard: WASD = d-pad, J = A, K = B, Z = Select, X = Start
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: [.down, .up]) { model.joypad.handle($0) }
        .onAppear {
            isFocused = true
        }
        .task {
            if let game {
                await model.run(game)
            }
        }
        .alert(isPresented: isShowingError, error: model.error) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
    }
}

/// A button that reports being held down and released, rather than a completed tap,
/// and sinks in while it is held.
struct JoypadButtonStyle: ButtonStyle {
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? -0.2 : 0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChange(isPressed)
            }
            // A soft tap on the way down only; releasing is silent
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: configuration.isPressed) { _, isPressed in
                isPressed
            }
    }
}

// No game: the preview only draws the console, it doesn't run anything
#Preview {
    GameBoyView(model: GameBoyViewModel(), game: nil)
}
