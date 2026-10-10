//
//  LibraryView.swift
//  GameBoyEmu
//

import SwiftUI
import UniformTypeIdentifiers

/// The first thing the app shows: the games that can be played, and their save data.
struct LibraryView: View {
    @State private var library = GameLibrary()
    /// The game being played, if any. Empty while the library itself is showing.
    @State private var path: [Game] = []
    @State private var isPickingROM = false
    @State private var gameToDeleteSaveOf: Game?
    @State private var gameToRename: Game?
    @State private var newName = ""
    @State private var error: GameBoyError?

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

                Section("Recent") {
                    if library.recent.isEmpty {
                        Text("Games you open appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.recent) { game in
                        row(for: game)
                    }
                }
            }
            .navigationTitle("Game Boy")
            .toolbar {
                Button("Open ROM…", systemImage: "folder") {
                    isPickingROM = true
                }
            }
            .navigationDestination(for: Game.self) { game in
                GameBoyView(game: game)
                    .navigationTitle(game.title)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            // ROM files have no registered type, so any file can be picked and the
            // library decides whether it is a game
            .fileImporter(isPresented: $isPickingROM, allowedContentTypes: [.data]) { result in
                do {
                    play(try library.importROM(from: result.get()))
                } catch {
                    show(error)
                }
            }
            .confirmationDialog(
                "Delete the save data of \(gameToDeleteSaveOf?.title ?? "")?",
                isPresented: isConfirmingDeletion,
                titleVisibility: .visible,
                presenting: gameToDeleteSaveOf
            ) { game in
                Button("Delete Save Data", role: .destructive) {
                    perform { try library.deleteSave(of: game) }
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
            }
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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            actions(for: game)
        }
        .swipeActions {
            actions(for: game)
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
                perform { try library.remove(game) }
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
        path = [game]
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
