# GameBoyEmu

A Game Boy and Game Boy Color emulator written in Swift and SwiftUI, for iOS 26 and macOS 26.

## Features

- Original Game Boy and Game Boy Color games, including double-speed mode
- Sound
- Save data, kept between launches
- Save data synced between your devices through iCloud
- A library of opened ROMs, with a file picker
- Touch controls with haptics, and keyboard controls (WASD, J/K, Z/X or N/M)
- Game controllers: pair one with the device and play (A and B as labelled on Xbox and Nintendo controllers, otherwise right button A and bottom button B; Menu and Options for Start and Select)
- Game Boy Color-style palettes for original Game Boy games
- Link cable between two nearby devices, over the local network (experimental)

## Running

Open `GameBoyEmu.xcodeproj` and run the **GameBoyEmu Optimized** scheme. The regular
**GameBoyEmu** scheme is an unoptimised build for previews and tests, and is too slow to play.

ROMs are not included. Open your own from the library screen.

## Not supported

- The real-time clock some cartridges have
- Super Game Boy features
- Cartridge types other than MBC1, MBC3 and MBC5
