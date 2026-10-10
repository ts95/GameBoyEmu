//
//  GameBoyView.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 23/06/2024.
//

import SwiftUI
import SwiftData

struct GameBoyView: View {
    // @StateObject keeps one GameBoy alive for the lifetime of the view. With @ObservedObject
    // a new one is created every time SwiftUI re-creates the view struct.
    @StateObject var gameBoy = GameBoy()
    @FocusState private var isFocused: Bool

    let gameBoyBeige = Color(red: 182/255, green: 183/255, blue: 178/255)

    var aspectRatio: CGFloat {
        CGFloat(displayBufferWidth) / CGFloat(displayBufferHeight)
    }

    var screen: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.white)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                canvas
            }
    }

    /// The current frame as a 160x144 grayscale image, scaled up without smoothing.
    @ViewBuilder
    var canvas: some View {
        // Color 0 is the lightest shade and 3 the darkest
        let shades: [UInt8] = [0xE6, 0xB3, 0x4D, 0x00]
        let pixels = Data(gameBoy.frame.map { shades[Int($0)] })

        if let provider = CGDataProvider(data: pixels as CFData),
           let image = CGImage(width: displayBufferWidth,
                               height: displayBufferHeight,
                               bitsPerComponent: 8,
                               bitsPerPixel: 8,
                               bytesPerRow: displayBufferWidth,
                               space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
        }
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
        .fontDesign(.monospaced)
        .textCase(.uppercase)
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
    }

    var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: {

            }, label: {
                Circle()
                    .fill(.pink)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Text("B")
                    }
            })

            Button(action: {

            }, label: {
                Circle()
                    .fill(.pink)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Text("A")
                    }
            })
        }
        .rotationEffect(.degrees(-20))
        .font(.title.bold())
        .foregroundStyle(.primary.opacity(0.5))
    }

    var optionButtons: some View {
        HStack(spacing: 16) {
            Button(action: {

            }, label: {
                Text("Select")
            })
            .rotationEffect(.degrees(-5))

            Button(action: {

            }, label: {
                Text("Start")
            })
            .rotationEffect(.degrees(-5))
        }
        .buttonStyle(.bordered)
        .font(.title3.bold())
        .foregroundStyle(.primary)
    }

    var body: some View {
        VStack {
            screen
            Spacer()
            joypad
            Spacer()
        }
        .padding()
        .background(gameBoyBeige.opacity(0.2))
        // Keyboard: WASD = d-pad, J = A, K = B, Z = Select, X = Start
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(phases: [.down, .up], action: gameBoy.joypad.onKeyPress)
        .onAppear {
            isFocused = true
        }
        .task {
            await startGameBoy()
        }
    }

    func startGameBoy() async {
        let rom = "pokemon_red"
        // let rom = "cpu_instrs"
        // let rom = "cpu_instrs"
        if let url = Bundle.main.url(forResource: rom, withExtension: "gb") {
            do {
                let romData = try Data(contentsOf: url)
                // Saves live in the app's own container, as <rom>.sav
                let saveURL = URL.applicationSupportDirectory.appending(path: "\(rom).sav")
                await gameBoy.start(withROM: romData, saveURL: saveURL)
            } catch {
                print(error)
            }
        } else {
            print("Couldn't find ROM")
        }
    }
}

#Preview {
    GameBoyView()
}
