//
//  LibraryView.swift
//  GameBoyEmu
//

import SwiftUI
import UniformTypeIdentifiers

/// The first thing the app shows: the games that can be played, and their save data.
struct LibraryView: View {
    @State private var library = GameLibrary()
    /// The games in progress, which keep their state while the library is showing.
    @State private var sessions = GameSessions()
    /// The game being played, if any. Empty while the library itself is showing.
    @State private var path: [Game] = []
    @State private var isPickingROM = false
    @State private var gameToDeleteSaveOf: Game?
    @State private var gameToRename: Game?
    @State private var newName = ""
    @State private var error: GameBoyError?
    @Environment(\.scenePhase) private var scenePhase
    /// The games whose save is the same here and in iCloud, as of the last sync.
    @State private var savesInCloud: Set<Game.ID> = []
    /// Whether the player is signed in to iCloud. Not known until the first sync.
    @State private var isCloudAvailable: Bool?
    @State private var isSyncing = false

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

                Section {
                    if library.recent.isEmpty {
                        #if os(tvOS)
                        // An Apple TV has no files to pick from
                        Text("Games you open on your other devices appear here.")
                            .foregroundStyle(.secondary)
                        #else
                        Text("Games you open appear here.")
                            .foregroundStyle(.secondary)
                        #endif
                    }
                    ForEach(library.recent) { game in
                        row(for: game)
                    }
                } header: {
                    Text("Recent")
                } footer: {
                    cloudFooter
                }
            }
            .navigationTitle("Game Boy")
            #if !os(tvOS)
            .toolbar {
                Button("Open ROM…", systemImage: "folder") {
                    isPickingROM = true
                }
            }
            #endif
            .navigationDestination(for: Game.self) { game in
                GameBoyView(model: sessions.model(for: game), game: game)
                    .navigationTitle(game.title)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            #if !os(tvOS)
            // ROM files have no registered type, so any file can be picked and the
            // library decides whether it is a game
            .fileImporter(isPresented: $isPickingROM, allowedContentTypes: [.data]) { result in
                do {
                    play(try library.importROM(from: result.get()))
                } catch {
                    show(error)
                }
            }
            #endif
            .confirmationDialog(
                "Delete the save data of \(gameToDeleteSaveOf?.title ?? "")?",
                isPresented: isConfirmingDeletion,
                titleVisibility: .visible,
                presenting: gameToDeleteSaveOf
            ) { game in
                Button("Delete Save Data", role: .destructive) {
                    perform {
                        try library.deleteSave(of: game)
                        // A game in progress still holds its save in memory and would write
                        // it back, so it has to start over too
                        sessions.end(game)
                        Task {
                            await CloudSync.forgetSave(of: game.id)
                        }
                    }
                }
            } message: { _ in
                Text("Your progress in this game will be lost. This can't be undone.")
            }
            .alert("Rename Game", isPresented: isRenaming, presenting: gameToRename) { game in
                TextField("Name", text: $newName)
                Button("Save") {
                    library.rename(game, to: newName)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Leave the name empty to go back to the game's own title.")
            }
            .alert(isPresented: isShowingError, error: error) { _ in
                Button("OK") {}
            } message: { error in
                Text(error.recoverySuggestion ?? "")
            }
            // Also runs when coming back from a game, which is when the save data has changed
            .onAppear {
                library.reload()
                Task {
                    // ponytail: the emulator writes the save a moment after the game is
                    // left, and there is no telling exactly when. A second is plenty.
                    try? await Task.sleep(for: .seconds(1))
                    await syncSaves()
                }
            }
            // Coming to the front fetches what other devices saved, and leaving sends
            // what was saved here
            .onChange(of: scenePhase) {
                Task {
                    await syncSaves()
                }
            }
            #if canImport(WatchConnectivity)
            .onReceive(NotificationCenter.default.publisher(for: WatchSync.didReceiveFile)) { notification in
                library.reload()
                // A save made on the watch has arrived. A game frozen here still holds the
                // older one in memory and would write it back, so it starts over from the
                // new save. One that is on screen right now is left to carry on.
                let games = library.included + library.recent
                if let game = games.first(where: { $0.id == notification.object as? String }), !path.contains(game) {
                    sessions.end(game)
                }
            }
            #endif
        }
    }

    private func row(for game: Game) -> some View {
        Button {
            play(game)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.headline)

                Group {
                    if let lastPlayed = game.lastPlayed {
                        Text("Played \(lastPlayed, format: .relative(presentation: .named))")
                    } else {
                        Text("Not played yet")
                    }

                    if let save = game.save {
                        Label {
                            Text("Saved \(save.modified, format: .relative(presentation: .named)), \(save.size.formatted(.byteCount(style: .file)))")
                        } icon: {
                            Image(systemName: "memorychip")
                        }
                    } else {
                        Text("No save data")
                    }

                    if game.save != nil, isCloudAvailable == true {
                        if savesInCloud.contains(game.id) {
                            Label("In iCloud", systemImage: "checkmark.icloud")
                        } else {
                            Label("Not in iCloud yet", systemImage: "icloud.slash")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if sessions.isInProgress(game) {
                    Label("In progress", systemImage: "play.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            actions(for: game)
        }
        #if !os(tvOS)
        .swipeActions {
            actions(for: game)
        }
        #endif
    }

    /// Says whether save data is being synced at all, below the list.
    @ViewBuilder
    private var cloudFooter: some View {
        if isSyncing {
            Label("Syncing with iCloud…", systemImage: "arrow.triangle.2.circlepath.icloud")
        } else if isCloudAvailable == true {
            Label("Games and save data sync between your devices through iCloud.", systemImage: "icloud")
        } else if isCloudAvailable == false {
            Label("Sign in to iCloud to sync games and save data between your devices.", systemImage: "icloud.slash")
        }
    }

    @ViewBuilder
    private func actions(for game: Game) -> some View {
        Button("Rename", systemImage: "pencil") {
            newName = game.title
            gameToRename = game
        }
        .tint(.blue)
        if !game.isIncluded {
            Button("Remove", systemImage: "minus.circle") {
                perform {
                    try library.remove(game)
                    sessions.end(game)
                    Task {
                        await CloudSync.forgetROM(named: game.romURL.lastPathComponent)
                    }
                }
            }
            .tint(.orange)
        }
        if game.save != nil {
            Button("Delete Save Data", systemImage: "trash", role: .destructive) {
                gameToDeleteSaveOf = game
            }
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding {
            gameToDeleteSaveOf != nil
        } set: { isConfirming in
            if !isConfirming {
                gameToDeleteSaveOf = nil
            }
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding {
            gameToRename != nil
        } set: { isRenaming in
            if !isRenaming {
                gameToRename = nil
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            error != nil
        } set: { isShowing in
            if !isShowing {
                error = nil
            }
        }
    }

    private func play(_ game: Game) {
        library.markPlayed(game)
        sessions.endIfFailed(game)
        Task {
            // Before the game reads its save: starting from an older one would end up
            // overwriting the newer one in iCloud
            await syncSaves(of: [game])
            path = [game]
        }
    }

    /// Brings save data in step with iCloud for the given games. Without any, it is every
    /// game's save data, and the ROMs as well.
    private func syncSaves(of games: [Game]? = nil) async {
        let isEverything = games == nil
        let games = games ?? library.included + library.recent
        isSyncing = true
        let outcome = await CloudSync.sync(saves: games.map(\.id), roms: isEverything)
        isSyncing = false

        isCloudAvailable = outcome.isAvailable
        savesInCloud.subtract(games.map(\.id))
        savesInCloud.formUnion(outcome.savesInCloud)
        library.reload()
        // A game frozen here still holds the older save in memory and would write it
        // back, so it starts over from the new one. One that is on screen right now is
        // left to carry on.
        for game in games where outcome.replacedSaves.contains(game.id) && !path.contains(game) {
            sessions.end(game)
        }
        #if os(iOS)
        // Whether made here or fetched from iCloud, a new save goes straight on to the watch
        WatchSync.sendNewSaves()
        #endif

        if outcome.didChangeROMs {
            await syncSaves() // Games that have just arrived haven't had their saves fetched
        }
    }

    /// Runs something that can fail, and tells the player if it does.
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            show(error)
        }
    }

    private func show(_ error: any Error) {
        self.error = error as? GameBoyError ?? .unexpected(reason: error.localizedDescription)
    }
}

#Preview {
    LibraryView()
}
