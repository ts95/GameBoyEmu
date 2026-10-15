//
//  WatchLibraryView.swift
//  GameBoyEmu Watch App
//

import SwiftUI

/// The games on the watch, which are the ones the phone has sent over.
struct WatchLibraryView: View {
    let sync: WatchSync

    @State private var library = GameLibrary()
    /// The games in progress, by game id. Leaving a game only freezes it: its model, and with
    /// it the whole machine, stays here until the player comes back, or the app quits.
    @State private var sessions: [Game.ID: WatchGameModel] = [:]
    /// The game being played, if any. Empty while the library itself is showing.
    @State private var path: [Game] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !library.included.isEmpty {
                    Section("Included") {
                        ForEach(library.included) { game in
                            row(for: game)
                        }
                    }
                }

                if !library.recent.isEmpty {
                    Section {
                        ForEach(library.recent) { game in
                            row(for: game)
                        }
                    } header: {
                        Text("From iPhone")
                    } footer: {
                        Text("Save data goes back to your iPhone after you play.")
                    }
                }
            }
            .overlay {
                if library.included.isEmpty && library.recent.isEmpty {
                    ContentUnavailableView(
                        "No Games",
                        systemImage: "iphone",
                        description: Text("Games you add in Game Boy Emu on your iPhone appear here.")
                    )
                }
            }
            .navigationTitle("Game Boy")
            .navigationDestination(for: Game.self) { game in
                if let model = sessions[game.id] {
                    WatchGameView(model: model, game: game, sync: sync)
                }
            }
            // Also runs when coming back from a game, which is when the save data has changed
            .onAppear {
                library.reload()
                sync.requestGames()
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchSync.didReceiveFile)) { notification in
                library.reload()
                // A newer save has come from the phone. A game frozen here still holds the
                // older one in memory and would write it back, so it starts over from the
                // new save. One that is on screen right now is left to carry on.
                if let id = notification.object as? String, !path.contains(where: { $0.id == id }) {
                    sessions[id] = nil
                }
            }
        }
    }

    private func row(for game: Game) -> some View {
        Button {
            play(game)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title)
                    .font(.headline)

                Group {
                    if let lastPlayed = game.lastPlayed {
                        Text("Played \(lastPlayed, format: .relative(presentation: .named))")
                    } else {
                        Text("Not played yet")
                    }

                    if let save = game.save {
                        Label("Saved \(save.modified, format: .relative(presentation: .named))", systemImage: "memorychip")
                    } else {
                        Text("No save data")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if isInProgress(game) {
                    Label("In progress", systemImage: "play.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .swipeActions {
            if isInProgress(game) {
                // From the last save, which is all a game that isn't in progress has
                Button("Start Over", systemImage: "arrow.counterclockwise") {
                    sessions[game.id] = nil
                }
                .tint(.orange)
            }
        }
    }

    private func isInProgress(_ game: Game) -> Bool {
        sessions[game.id].map { !$0.hasFailed } ?? false
    }

    /// Carries on with a game, or starts it if it isn't in progress.
    private func play(_ game: Game) {
        library.markPlayed(game)
        if !isInProgress(game) {
            sessions[game.id] = WatchGameModel()
        }
        path = [game]
    }
}
