# GameBoyEmu

A Game Boy and Game Boy Color emulator written in Swift and SwiftUI, for iOS 26 and macOS 26,
with a companion app for Apple Watch.

## Features

- Original Game Boy and Game Boy Color games, including double-speed mode
- Sound
- Save data, kept between launches
- Save data synced between your devices through iCloud; the newest save wins
- A library of opened ROMs, with a file picker, showing each game's save, whether it is in iCloud, and whether the game is in progress
- Touch controls with haptics, and keyboard controls (WASD, J/K, Z/X or N/M)
- Game controllers: pair one with the device and play (A and B as labelled on Xbox and Nintendo controllers, otherwise right button A and bottom button B; Menu and Options for Start and Select)
- Game Boy Color-style palettes for original Game Boy games
- Link cable between two nearby devices, over the local network: one hosts, the other joins
- Apple Watch app (experimental, no sound): plays the games and saves from the iPhone app. Tilt the wrist for the d-pad, double tap or tap the screen for A, flick the wrist for B, and turn the Digital Crown for Start and Select

## Running

Open `GameBoyEmu.xcodeproj` and run the **GameBoyEmu Optimized** scheme. The regular
**GameBoyEmu** scheme is an unoptimised build for previews and tests, and is too slow to play.

The **GameBoyEmu Watch App** scheme runs the watch app, which is also installed along with
the iPhone app.

ROMs are not included. Open your own from the library screen. They aren't synced through
iCloud: add the same ROM file, under the same name, on each device, and its save follows.

To build under your own developer team, change the bundle identifiers and the iCloud
container in `GameBoyEmu.entitlements`. iCloud needs a paid developer account.

## Not supported

- The real-time clock some cartridges have
- Super Game Boy features
- Cartridge types other than MBC1, MBC3 and MBC5
