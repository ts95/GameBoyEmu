//
//  GameBoyEmuApp.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 23/06/2024.
//

import SwiftUI
import SwiftData

@main
struct GameBoyEmuApp: App {
    #if canImport(WatchConnectivity)
    // Set up at launch rather than by a view: the watch can wake the app in the
    // background, where no view ever appears
    private let watchSync = WatchSync.shared
    #endif

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
    }
}
