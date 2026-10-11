//
//  WatchLibraryView.swift
//  GameBoyEmu Watch App
//

import SwiftUI

/// The games on the watch, which are the ones the phone has sent over.
struct WatchLibraryView: View {
    let sync: WatchSync

    @State private var library = GameLibrary()

    var body: some View {
        NavigationStack {
            List(library.recent) { game in
                NavigationLink(game.title, value: game)
            }
            .overlay {
                if library.recent.isEmpty {
                    ContentUnavailableView(
                        "No Games",
                        systemImage: "iphone",
                        description: Text("Games you add in Game Boy Emu on your iPhone appear here.")
                    )
                }
            }
            .navigationTitle("Game Boy")
            .navigationDestination(for: Game.self) { game in
                WatchGameView(game: game, sync: sync)
            }
            // Also runs when coming back from a game
            .onAppear {
                library.reload()
                sync.requestGames()
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchSync.didReceiveFile)) { _ in
                library.reload()
            }
        }
    }
}
