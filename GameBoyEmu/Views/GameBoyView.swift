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
    @State private var isShowingLink = false
    @State private var keyboard = KeyboardControls()
    @State private var isShowingMenu = false
    @Environment(\.dismiss) private var dismiss

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

    /// Steps through the speeds. Stuck at the real one while the link cable is in use.
    var speedButton: some View {
        Button {
            model.cycleSpeed()
        } label: {
            Text("\(model.effectiveSpeed)×")
                .font(.title3.bold())
                .frame(width: 44, height: 32)
                .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.effectiveSpeed > 1 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .disabled(model.linkState != .unplugged)
        .accessibilityLabel("Speed")
        .accessibilityValue("\(model.effectiveSpeed) times")
    }

    var linkButton: some View {
        Button {
            isShowingLink = true
        } label: {
            Image(systemName: "cable.connector")
                .font(.title3)
                .frame(width: 44, height: 32)
                // Pulses while a link is being set up
                .symbolEffect(.pulse, isActive: model.linkState == .hosting || model.linkState == .joining)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.linkState == .linked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .accessibilityLabel("Link cable")
        .accessibilityValue(model.linkState == .linked ? "Linked" : "Unplugged")
    }

    /// The buttons that belong to the emulator rather than the console.
    var utilityButtons: some View {
        HStack(spacing: 0) {
            speedButton
            linkButton
            muteButton
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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
            utilityButtons
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
                    utilityButtons
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
        // Tilt the cross towards the pressed direction, like the real rocker. This follows
        // the model rather than the touch, so the keyboard and a controller move it too.
        .rotation3DEffect(.degrees(model.joypad.dPadState == .idle ? 0 : 12), axis: dPadTiltAxis)
        .animation(.spring(duration: 0.15), value: model.joypad.dPadState)
        .contentShape(Rectangle())
        #if !os(tvOS)
        // One gesture for the whole cross, so a thumb can slide from one direction to another.
        // The gesture state falls back to .idle when the finger lifts or the touch is cancelled.
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dPadState) { value, state, _ in
                    state = dPadDirection(at: value.location)
                }
        )
        #endif
        .onChange(of: dPadState) { _, newState in
            model.joypad.dPadState = newState
        }
        // A faint tick for each direction pressed, including when sliding from one to the next
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.4), trigger: dPadState) { _, newState in
            newState != .idle
        }
    }

    var dPadTiltAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        switch model.joypad.dPadState {
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
            actionButton("B", \.bButtonPressed)
            actionButton("A", \.aButtonPressed)
        }
        .rotationEffect(.degrees(-20))
        .font(.title.bold())
        .foregroundStyle(.primary.opacity(0.5))
    }

    func actionButton(_ title: String, _ button: WritableKeyPath<JoypadState, Bool>) -> some View {
        Button(action: {}, label: {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 70, height: 70)
                .overlay {
                    Text(title)
                }
        })
        .buttonStyle(JoypadButtonStyle(isHeld: model.joypad[keyPath: button]) {
            model.joypad[keyPath: button] = $0
        })
    }

    var optionButtons: some View {
        HStack(spacing: 16) {
            selectButton
            startButton
        }
    }

    var selectButton: some View {
        optionButton("Select", \.selectButtonPressed)
    }

    var startButton: some View {
        optionButton("Start", \.startButtonPressed)
    }

    func optionButton(_ title: String, _ button: WritableKeyPath<JoypadState, Bool>) -> some View {
        Button(action: {}, label: {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .fixedSize() // Never wrap a label onto two lines
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        })
        .buttonStyle(JoypadButtonStyle(isHeld: model.joypad[keyPath: button]) {
            model.joypad[keyPath: button] = $0
        })
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

    /// On a television there is nothing to touch, so the console's controls are left out
    /// and the screen gets the room. The remote does the pressing.
    var televisionLayout: some View {
        VStack(spacing: 32) {
            screen
            Text(model.isUsingGamepad
                 ? "Controller: d-pad or stick, A, B, Start and Select  ·  Either shoulder button: menu"
                 : "Clickpad: move, click for A  ·  Play/Pause: B  ·  Back: Start, Select and more")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    var body: some View {
        Group {
            #if os(tvOS)
            televisionLayout
            #else
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
            #endif
        }
        .fontDesign(.monospaced)
        .textCase(.uppercase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gameBoyBeige.opacity(0.2))
        // Keyboard: WASD = d-pad, J = A, K = B, Z or N = Select, X or M = Start
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: .all) { keyboard.handle($0, joypad: &model.joypad) }
        .onAppear {
            isFocused = true
        }
        .task {
            if let game {
                await model.run(game)
            }
        }
        .onDisappear {
            model.unplugLink() // The cable doesn't reach outside the game
        }
        .onChange(of: model.error) { _, error in
            if error != nil {
                isShowingLink = false // Make way for the alert
            }
        }
        .onChange(of: isShowingMenu || isShowingLink) { _, isBusy in
            model.ignoresController = isBusy
        }
        #if os(tvOS)
        // The remote's Back button brings up what the remote has no buttons for. A game
        // controller sends the same command from its B button, which is a button in the
        // game, and has a Start and Select of its own.
        .onExitCommand {
            if !model.isUsingGamepad {
                isShowingMenu = true
            }
        }
        .onChange(of: model.menuRequests) {
            isShowingMenu = true
        }
        .confirmationDialog(game?.title ?? "Game Boy", isPresented: $isShowingMenu, titleVisibility: .visible) {
            Button("Start") {
                model.tap(\.startButtonPressed)
            }
            Button("Select") {
                model.tap(\.selectButtonPressed)
            }
            Button(model.isMuted ? "Unmute" : "Mute") {
                model.isMuted.toggle()
            }
            Button("Speed: \(model.effectiveSpeed)×") {
                model.cycleSpeed()
            }
            .disabled(model.linkState != .unplugged)
            Button("Link Cable…") {
                isShowingLink = true
            }
            Button("Back to Library") {
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        #endif
        // Last, so that the sheet doesn't pick up the console's lettering
        .sheet(isPresented: $isShowingLink) {
            LinkView(model: model, hostName: game?.title ?? "Game Boy")
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
    /// Whether the game sees the button as held, whatever is holding it: a finger, the
    /// keyboard or a controller.
    let isHeld: Bool
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        let isDown = isHeld || configuration.isPressed
        configuration.label
            .scaleEffect(isDown ? 0.88 : 1)
            .brightness(isDown ? -0.2 : 0)
            .animation(.spring(duration: 0.15), value: isDown)
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
