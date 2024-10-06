//
//  GameBoyView.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 23/06/2024.
//

import SwiftUI
import SwiftData

struct GameBoyView: View {
    @ObservedObject var gameBoy = GameBoy()

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

    var canvas: Canvas<EmptyView> {
        Canvas { context, size in
            let pixelWidth = size.width / CGFloat(displayBufferWidth)
            let pixelHeight = size.height / CGFloat(displayBufferHeight)

            for y in 0..<displayBufferHeight {
                for x in 0..<displayBufferWidth {
                    let color = getPixelColor(x: x, y: y)
                    let rect = CGRect(x: CGFloat(x) * pixelWidth,
                                      y: CGFloat(y) * pixelHeight,
                                      width: pixelWidth,
                                      height: pixelHeight)
                    context.fill(Path(rect), with: .color(color))
                }
            }
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
        .task {
            await startGameBoy()
        }
    }

    func startGameBoy() async {
        // let rom = "pokemon_red"
        // let rom = "cpu_instrs"
        let rom = "cpu_instrs"
        if let url = Bundle.main.url(forResource: rom, withExtension: "gb") {
            do {
                let romData = try Data(contentsOf: url)
                await gameBoy.start(withROM: romData)
            } catch {
                print(error)
            }
        } else {
            print("Couldn't find ROM")
        }
    }

    func getPixelColor(x: Int, y: Int) -> Color {
        let pixelColor = gameBoy.ppu[x, y]

        switch pixelColor {
        case .light:
            return .black.opacity(0.1)
        case .lightGray:
            return .black.opacity(0.3)
        case .darkGray:
            return .black.opacity(0.7)
        case .dark:
            return .black
        }
    }
}

#Preview {
    GameBoyView()
}
