//
//  ContentView.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 23/06/2024.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State var gameBoy = GameBoy()

    var body: some View {
        Text("Game Boy Emulator")
            .task {
                if let url = Bundle.main.url(forResource: "Pokemon Red Version", withExtension: "gb") {
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
    }
}

#Preview {
    ContentView()
}
