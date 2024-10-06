//
//  GameBoyPPU.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 03/07/2024.
//

import Foundation

let displayBufferWidth = 160
let displayBufferHeight = 144

enum PixelColor: UInt8 {
    case light
    case lightGray
    case darkGray
    case dark
}

/// The PPU mode states.
///
/// The Game Boy PPU operates in four distinct modes during each frame.
enum PPUMode {
    /// The period when the PPU is idle and the CPU can access video RAM (VRAM).
    ///
    /// - Duration: 204 clock cycles.
    /// - Occurs: After each of the 144 visible scanlines.
    case hBlank

    /// The period when the screen is not being updated and the PPU is idle.
    ///
    /// - Duration: 4560 clock cycles (10 scanlines).
    /// - Occurs: After all scanlines are drawn, making up about 10% of the total frame time.
    /// - Interrupt: Generates a VBlank interrupt (INT 40h).
    case vBlank

    /// The period when the PPU scans the Object Attribute Memory (OAM) to determine which sprites will be drawn on the current scanline.
    ///
    /// - Duration: 80 clock cycles.
    /// - Occurs: At the beginning of each scanline.
    case oamSearch

    /// The period when the PPU fetches tile data and renders pixels to the screen for the current scanline.
    ///
    /// - Duration: 172 clock cycles.
    /// - Access: During this mode, VRAM access is restricted.
    case pixelTransfer
}

/// The Game Boy Picture Processing Unit (PPU).
///
/// The PPU is responsible for rendering the display in the Game Boy.
/// It operates based on a sequence of states known as the PPU mode, which include HBlank, VBlank, OAM Search, and Pixel Transfer.
///
/// - Note: The PPU interacts closely with video RAM (VRAM) and Object Attribute Memory (OAM), and generates interrupts during VBlank and HBlank periods.
class GameBoyPPU<AddressBus: AddressBusProtocol>: ObservableObject {

    var addressBus: AddressBus

    /// This property indicates the current operational mode of the PPU, which can be one of four states:
    /// - `.hBlank`: The PPU is in the horizontal blank period.
    /// - `.vBlank`: The PPU is in the vertical blank period.
    /// - `.oamSearch`: The PPU is searching OAM for sprites.
    /// - `.pixelTransfer`: The PPU is transferring pixel data to the display.
    @Published var mode = PPUMode.oamSearch

    /// The number of clock cycles the PPU has spent in the current mode.
    ///
    /// This property is incremented with each step and is used to determine when the PPU should transition
    /// to the next mode.
    var modeClock = 0

    /// The current scanline being processed by the PPU.
    ///
    /// This property ranges from 0 to 153, with 0 to 143 representing visible scanlines,
    /// and 144 to 153 representing the vertical blank period.
    var currentScanline: UInt8 = 0

    /// The display buffer that holds the pixel data for the entire screen.
    ///
    /// This property is an array of 160x144 elements, each representing a pixel on the Game Boy display.
    /// The buffer is used to store the rendered pixel values before they are displayed on the screen.
    @Published var displayBuffer: [UInt8] = Array(repeating: 0, count: displayBufferWidth * displayBufferHeight)

    init(addressBus: AddressBus) {
        self.addressBus = addressBus
    }

    /// Returns the color value of a pixel given its coordinates.
    subscript(x: Int, y: Int) -> PixelColor {
        get {
            return PixelColor(rawValue: displayBuffer[y * displayBufferWidth + x])!
        }
        set(color) {
            displayBuffer[y * displayBufferWidth + x] = color.rawValue
        }
    }

    /// Advances the PPU by the given number of cycles.
    ///
    /// - Parameter cycles: The number of cycles to advance the PPU.
    func step(cycles: Int) {
        modeClock += cycles

        switch mode {
        case .oamSearch:
            if modeClock >= 80 {
                modeClock %= 80
                mode = .pixelTransfer
            }
        case .pixelTransfer:
            if modeClock >= 172 {
                modeClock %= 172
                mode = .hBlank
                renderScanline()
            }
        case .hBlank:
            if modeClock >= 204 {
                modeClock %= 204
                currentScanline += 1

                if currentScanline == displayBufferHeight {
                    mode = .vBlank
                    triggerVBlankInterrupt()
                } else {
                    mode = .oamSearch
                }
            }
        case .vBlank:
            if modeClock >= 456 {
                modeClock %= 456
                currentScanline += 1

                if currentScanline > 153 {
                    mode = .oamSearch
                    currentScanline = 0
                }
            }
        }
    }

    private func triggerVBlankInterrupt() {
        // Set the VBlank interrupt flag (bit 0) in the IF register
        addressBus[0xFF0F] |= 0x01
    }

    /// Retrieves the actual color value from the palette based on the color number.
    ///
    /// The Game Boy uses a 2-bit color format to represent four possible colors. Each pixel color is determined by a 2-bit value
    /// (ranging from 0 to 3), where 0 represents the lightest color and 3 represents the darkest color. The color values are stored
    /// in the palette register, where each color occupies two bits. The palette register's format is as follows:
    ///
    /// - Bits 1-0: Color 0 (lightest)
    /// - Bits 3-2: Color 1
    /// - Bits 5-4: Color 2
    /// - Bits 7-6: Color 3 (darkest)
    ///
    /// The method extracts the appropriate color bits from the palette and combines them to return the final color value.
    ///
    /// - Parameters:
    ///   - colorNum: The 2-bit color number (0 to 3) for the pixel.
    ///   - paletteAddr: The address of the palette register in addressBus.
    /// - Returns: The 2-bit color value extracted from the palette.
    private func getColor(colorNum: UInt8, paletteAddr: Int) -> UInt8 {
        let palette = addressBus[paletteAddr] // Palette data
        let hi = (palette >> (colorNum * 2 + 1)) & 1 // High bit of the color number
        let lo = (palette >> (colorNum * 2)) & 1 // Low bit of the color number
        return (hi << 1) | lo // Combine high and low bits to get the actual color
    }

    private func renderScanline() {
        // Render the current scanline to the display buffer
        let lcdc = addressBus[0xFF40] // LCD Control register
        let scx = addressBus[0xFF43]  // Scroll X register
        let scy = addressBus[0xFF42]  // Scroll Y register
        let ly = currentScanline  // Current scanline

        // Determine if background/window and sprites are enabled
        let bgEnabled = lcdc & 0x01 != 0      // Bit 0 of LCDC: Background display
        let windowEnabled = lcdc & 0x20 != 0  // Bit 5 of LCDC: Window display
        let spritesEnabled = lcdc & 0x02 != 0 // Bit 1 of LCDC: Sprite display

        // Render background
        if bgEnabled {
            renderBackgroundLine(scx: scx, scy: scy, ly: ly)
        }

        // Render window (if enabled and visible)
        if windowEnabled {
            let wy = addressBus[0xFF4A]     // Window Y position
            let wx = addressBus[0xFF4B] - 7 // Window X position, offset by 7 as the window position starts at WX=7
            if ly >= wy {
                renderWindowLine(wx: wx, wy: wy, ly: ly)
            }
        }

        // Render sprites
        if spritesEnabled {
            renderSpritesLine(ly: ly)
        }
    }

    /// Renders the background line for the given scanline (ly).
    ///
    /// - Parameters:
    ///   - scx: The scroll X value.
    ///   - scy: The scroll Y value.
    ///   - ly: The current scanline.
    private func renderBackgroundLine(scx: UInt8, scy: UInt8, ly: UInt8) {
        let lcdc = addressBus[0xFF40] // LCD Control register
        let tileMapBase = (lcdc & 0x08 != 0) ? 0x9C00 : 0x9800 // Bit 3 of LCDC: Background Tile Map Display Select
        let tileDataBase = (lcdc & 0x10 != 0) ? 0x8000 : 0x8800 // Bit 4 of LCDC: Background & Window Tile Data Select

        let yPos = UInt16((UInt16(ly) + UInt16(scy)) % 256) // Vertical position in the background, wrapping at 256
        let tileRow = yPos / 8 // Each tile is 8 pixels high

        for x in 0..<displayBufferWidth {
            let xPos = UInt16((UInt16(x) + UInt16(scx)) % 256) // Horizontal position in the background, wrapping at 256
            let tileCol = xPos / 8 // Each tile is 8 pixels wide
            let tileIndexAddr = UInt16(tileMapBase) + tileRow * 32 + tileCol // Calculate the tile index address (32 tiles per row)
            let tileIndex = addressBus[Int(tileIndexAddr)]

            let tileAddr: UInt16
            if tileDataBase == 0x8000 {
                tileAddr = UInt16(tileDataBase) + UInt16(tileIndex) * 16 // Each tile is 16 bytes
            } else {
                tileAddr = UInt16(tileDataBase) + (UInt16(Int8(bitPattern: tileIndex)) + 128) * 16 // Signed tile index offset by 128
            }

            let lineInTile = yPos % 8 // Current line in the tile (0-7)
            let data1 = addressBus[Int(tileAddr) + Int(lineInTile) * 2] // Tile data for the current line
            let data2 = addressBus[Int(tileAddr) + Int(lineInTile) * 2 + 1]

            let colorBit = 7 - (xPos % 8) // Bit position in the data byte (0-7)
            let colorNum = ((data2 >> colorBit) & 1) << 1 | ((data1 >> colorBit) & 1) // Calculate color number (2 bits)

            let color = getColor(colorNum: colorNum, paletteAddr: 0xFF47) // Get the actual color from the palette
            displayBuffer[Int(ly) * displayBufferWidth + x] = color // Write the color to the display buffer
        }
    }

    /// Renders the window line for the given scanline (ly).
    ///
    /// - Parameters:
    ///   - wx: The window X position.
    ///   - wy: The window Y position.
    ///   - ly: The current scanline.
    private func renderWindowLine(wx: UInt8, wy: UInt8, ly: UInt8) {
        if wx >= displayBufferWidth || wy >= displayBufferHeight || ly < wy {
            return // If the window is out of bounds or not yet visible, do nothing
        }

        let lcdc = addressBus[0xFF40] // LCD Control register
        let tileMapBase = (lcdc & 0x40 != 0) ? 0x9C00 : 0x9800 // Bit 6 of LCDC: Window Tile Map Display Select
        let tileDataBase = (lcdc & 0x10 != 0) ? 0x8000 : 0x8800 // Bit 4 of LCDC: Background & Window Tile Data Select

        let yPos = UInt16(ly - wy) // Vertical position in the window
        let tileRow = yPos / 8 // Each tile is 8 pixels high

        for x in 0..<displayBufferWidth {
            let xPos = UInt16(x + Int(wx) - 7) // Horizontal position in the window, offset by 7
            if xPos >= displayBufferWidth {
                continue // If the x position is out of bounds, skip
            }
            let tileCol = xPos / 8 // Each tile is 8 pixels wide
            let tileIndexAddr = UInt16(tileMapBase) + tileRow * 32 + tileCol // Calculate the tile index address (32 tiles per row)
            let tileIndex = addressBus[Int(tileIndexAddr)]

            let tileAddr: UInt16
            if tileDataBase == 0x8000 {
                tileAddr = UInt16(tileDataBase) + UInt16(tileIndex) * 16 // Each tile is 16 bytes
            } else {
                tileAddr = UInt16(tileDataBase) + (UInt16(Int8(bitPattern: tileIndex)) + 128) * 16 // Signed tile index offset by 128
            }

            let lineInTile = yPos % 8 // Current line in the tile (0-7)
            let data1 = addressBus[Int(tileAddr) + Int(lineInTile) * 2] // Tile data for the current line
            let data2 = addressBus[Int(tileAddr) + Int(lineInTile) * 2 + 1]

            let colorBit = 7 - (xPos % 8) // Bit position in the data byte (0-7)
            let colorNum = ((data2 >> colorBit) & 1) << 1 | ((data1 >> colorBit) & 1) // Calculate color number (2 bits)

            let color = getColor(colorNum: colorNum, paletteAddr: 0xFF47) // Get the actual color from the palette
            displayBuffer[Int(ly) * displayBufferWidth + Int(xPos)] = color // Write the color to the display buffer
        }
    }

    /// Renders the sprites for the given scanline (ly).
    ///
    /// - Parameter ly: The current scanline.
    private func renderSpritesLine(ly: UInt8) {
        let lcdc = addressBus[0xFF40] // LCD Control register
        let spriteHeight = (lcdc & 0x04 != 0) ? 16 : 8 // Bit 2 of LCDC: Sprite size (8x16 or 8x8)

        for i in 0..<40 { // Maximum of 40 sprites
            let spriteAddr = 0xFE00 + i * 4 // Each sprite uses 4 bytes in OAM
            let yPos = Int(addressBus[spriteAddr]) - spriteHeight // Y position of the sprite (offset by sprite height)
            let xPos = Int(addressBus[spriteAddr + 1]) - 8 // X position of the sprite (offset by 8)
            let tileIndex = addressBus[spriteAddr + 2] // Tile index
            let attributes = addressBus[spriteAddr + 3] // Sprite attributes

            if ly >= yPos && ly < yPos + spriteHeight {
                // Check if the current scanline intersects with the sprite

                // Bit 6 of attributes: Vertical flip
                let lineInTile = (attributes & 0x40 != 0) ? spriteHeight - 1 - Int(ly) - yPos : Int(ly) - yPos
                let tileAddr = 0x8000 + UInt16(tileIndex) * 16 // Each tile is 16 bytes
                let data1 = addressBus[Int(tileAddr) + Int(lineInTile) * 2] // Tile data for the current line
                let data2 = addressBus[Int(tileAddr) + Int(lineInTile) * 2 + 1]

                for x in 0..<8 {
                    // Bit 5 of attributes: Horizontal flip
                    let colorBit = (attributes & 0x20 != 0) ? x : 7 - x
                    let colorNum = ((data2 >> colorBit) & 1) << 1 | ((data1 >> colorBit) & 1) // Calculate color number (2 bits)

                    if colorNum == 0 {
                        continue // Color number 0 is transparent
                    }

                    // Bit 4 of attributes: Palette number
                    let paletteAddr = attributes & 0x10 != 0 ? 0xFF49 : 0xFF48
                    let color = getColor(colorNum: colorNum, paletteAddr: paletteAddr)
                    let xPixel = xPos + x

                    if (0..<displayBufferWidth).contains(xPixel) {
                        displayBuffer[Int(ly) * displayBufferWidth + xPixel] = color // Write the color to the display buffer
                    }
                }
            }
        }
    }
}
