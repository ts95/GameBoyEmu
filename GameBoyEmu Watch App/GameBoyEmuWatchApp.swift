//
//  GameBoyEmuWatchApp.swift
//  GameBoyEmu Watch App
//

import SwiftUI

/// The emulator on the wrist. The emulation itself is the phone app's, compiled into this
/// app as well through the links in the Shared folder; only what is on screen and how it
/// is controlled are the watch's own.
@main
struct GameBoyEmuWatchApp: App {
    private let sync = WatchSync.shared

    var body: some Scene {
        WindowGroup {
            WatchLibraryView(sync: sync)
        }
    }
}
