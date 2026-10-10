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
class GameBoyPPU<AddressBus: AddressBusProtocol> {

    var addressBus: AddressBus

    /// This property indicates the current operational mode of the PPU, which can be one of four states:
    /// - `.hBlank`: The PPU is in the horizontal blank period.
    /// - `.vBlank`: The PPU is in the vertical blank period.
    /// - `.oamSearch`: The PPU is searching OAM for sprites.
    /// - `.pixelTransfer`: The PPU is transferring pixel data to the display.
    var mode = PPUMode.oamSearch

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
    var displayBuffer: [UInt8] = Array(repeating: 0, count: displayBufferWidth * displayBufferHeight)

    /// The background/window color numbers (before the palette) of the scanline being drawn.
    /// Sprites need them, because a sprite can ask to be drawn behind non-zero background pixels.
    private var lineColorNumbers: [UInt8] = Array(repeating: 0, count: displayBufferWidth)

    /// How many window lines have been drawn this frame. The window keeps its own line counter,
    /// it does not simply follow the scanline number.
    private var windowLine = 0

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
    /// The PPU is not something the game calls into. It is a separate machine that keeps
    /// drawing 60 frames per second on its own, and the game finds out where it is by
    /// reading the LY (0xFF44) and STAT (0xFF41) registers or by waiting for interrupts.
    ///
    /// - Parameter cycles: The number of cycles to advance the PPU.
    /// - Returns: `true` when a frame was just completed (the PPU entered VBlank).
    @discardableResult
    func step(cycles: Int) -> Bool {
        guard addressBus[0xFF40] & 0x80 != 0 else {
            // Bit 7 of LCDC switches the whole LCD off. The PPU then stops and LY stays at 0.
            modeClock = 0
            currentScanline = 0
            windowLine = 0
            mode = .oamSearch
            addressBus[0xFF44] = 0
            addressBus[0xFF41] &= 0xF8
            return false
        }

        modeClock += cycles

        switch mode {
        case .oamSearch:
            if modeClock >= 80 {
                modeClock -= 80
                enter(mode: .pixelTransfer)
            }
        case .pixelTransfer:
            if modeClock >= 172 {
                modeClock -= 172
                renderScanline()
                enter(mode: .hBlank)
            }
        case .hBlank:
            if modeClock >= 204 {
                modeClock -= 204
                currentScanline += 1

                if currentScanline == displayBufferHeight {
                    enter(mode: .vBlank)
                    addressBus[0xFF0F] |= 0x01 // Request the VBlank interrupt (bit 0 of IF)
                    return true
                } else {
                    enter(mode: .oamSearch)
                }
            }
        case .vBlank:
            if modeClock >= 456 {
                modeClock -= 456
                currentScanline += 1

                if currentScanline > 153 {
                    currentScanline = 0
                    windowLine = 0
                    enter(mode: .oamSearch)
                } else {
                    enter(mode: .vBlank) // Same mode, but LY has to be updated
                }
            }
        }

        return false
    }

    /// Switches mode and publishes the PPU's position to the LY and STAT registers,
    /// requesting the LCD STAT interrupt if the game asked for one.
    private func enter(mode newMode: PPUMode) {
        let modeChanged = mode != newMode
        let lineChanged = addressBus[0xFF44] != currentScanline
        mode = newMode

        let modeBits: UInt8
        let modeInterruptEnableBit: UInt8
        switch newMode {
        case .hBlank:        (modeBits, modeInterruptEnableBit) = (0, 0x08)
        case .vBlank:        (modeBits, modeInterruptEnableBit) = (1, 0x10)
        case .oamSearch:     (modeBits, modeInterruptEnableBit) = (2, 0x20)
        case .pixelTransfer: (modeBits, modeInterruptEnableBit) = (3, 0x00)
        }

        let isLineCompareMatch = currentScanline == addressBus[0xFF45] // LY == LYC
        // Bits 3-6 of STAT belong to the game (interrupt enables), bits 0-2 belong to the PPU
        let stat = (addressBus[0xFF41] & 0x78) | (isLineCompareMatch ? 0x04 : 0) | modeBits

        addressBus[0xFF44] = currentScanline
        addressBus[0xFF41] = stat

        if (modeChanged && stat & modeInterruptEnableBit != 0) ||
            (lineChanged && isLineCompareMatch && stat & 0x40 != 0) {
            addressBus[0xFF0F] |= 0x02 // Request the LCD STAT interrupt (bit 1 of IF)
        }
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
    /// - Parameters:
    ///   - colorNum: The 2-bit color number (0 to 3) for the pixel.
    ///   - paletteAddr: The address of the palette register in addressBus.
    /// - Returns: The 2-bit color value extracted from the palette.
    private func getColor(colorNum: UInt8, paletteAddr: Int) -> UInt8 {
        (addressBus[paletteAddr] >> (colorNum * 2)) & 0x03
    }

    private func renderScanline() {
        // Render the current scanline to the display buffer
        let lcdc = addressBus[0xFF40] // LCD Control register
        let ly = Int(currentScanline) // Current scanline

        // Determine if background/window and sprites are enabled
        let bgEnabled = lcdc & 0x01 != 0      // Bit 0 of LCDC: Background and window display
        let windowEnabled = lcdc & 0x20 != 0  // Bit 5 of LCDC: Window display
        let spritesEnabled = lcdc & 0x02 != 0 // Bit 1 of LCDC: Sprite display

        // The window is a second background layer that doesn't scroll, drawn on top of the
        // background from (WX - 7, WY) to the bottom right corner. Games use it for HUDs and menus.
        let windowX = Int(addressBus[0xFF4B]) - 7 // WX is offset by 7
        let isWindowVisible = bgEnabled && windowEnabled && ly >= Int(addressBus[0xFF4A]) && windowX < displayBufferWidth

        let bgTileMapBase = (lcdc & 0x08 != 0) ? 0x9C00 : 0x9800     // Bit 3 of LCDC: Background tile map
        let windowTileMapBase = (lcdc & 0x40 != 0) ? 0x9C00 : 0x9800 // Bit 6 of LCDC: Window tile map
        let scx = Int(addressBus[0xFF43]) // Scroll X register
        let scy = Int(addressBus[0xFF42]) // Scroll Y register

        for x in 0..<displayBufferWidth {
            let colorNum: UInt8
            if isWindowVisible && x >= windowX {
                colorNum = tileColorNumber(tileMapBase: windowTileMapBase, x: x - windowX, y: windowLine)
            } else if bgEnabled {
                // The background is a 256x256 pixel map that wraps around; SCX/SCY pick which
                // part of it is visible through the 160x144 screen.
                colorNum = tileColorNumber(tileMapBase: bgTileMapBase, x: (x + scx) % 256, y: (ly + scy) % 256)
            } else {
                colorNum = 0
            }

            lineColorNumbers[x] = colorNum
            displayBuffer[ly * displayBufferWidth + x] = getColor(colorNum: colorNum, paletteAddr: 0xFF47)
        }

        if isWindowVisible {
            windowLine += 1
        }

        // Render sprites
        if spritesEnabled {
            renderSpritesLine(ly: ly)
        }
    }

    /// Looks up the color number (0-3) of one pixel of a 256x256 tile map.
    ///
    /// A tile map doesn't contain pixels. It is a 32x32 grid of tile numbers, and each tile
    /// number refers to an 8x8 pixel picture stored elsewhere in VRAM (2 bytes per row of pixels).
    ///
    /// - Parameters:
    ///   - tileMapBase: The address of the tile map, 0x9800 or 0x9C00.
    ///   - x: The horizontal pixel position in the map.
    ///   - y: The vertical pixel position in the map.
    private func tileColorNumber(tileMapBase: Int, x: Int, y: Int) -> UInt8 {
        let tileIndex = addressBus[tileMapBase + (y / 8) * 32 + x / 8] // 32 tiles per row

        let tileAddr: Int
        if addressBus[0xFF40] & 0x10 != 0 { // Bit 4 of LCDC: Background & window tile data select
            tileAddr = 0x8000 + Int(tileIndex) * 16 // Each tile is 16 bytes
        } else {
            tileAddr = 0x9000 + Int(Int8(bitPattern: tileIndex)) * 16 // Signed tile index around 0x9000
        }

        let data1 = addressBus[tileAddr + (y % 8) * 2] // Tile data for the current line
        let data2 = addressBus[tileAddr + (y % 8) * 2 + 1]

        let colorBit = 7 - (x % 8) // The leftmost pixel is stored in bit 7
        return ((data2 >> colorBit) & 1) << 1 | ((data1 >> colorBit) & 1)
    }

    /// Renders the sprites for the given scanline (ly).
    ///
    /// - Parameter ly: The current scanline.
    private func renderSpritesLine(ly: Int) {
        let lcdc = addressBus[0xFF40] // LCD Control register
        let spriteHeight = (lcdc & 0x04 != 0) ? 16 : 8 // Bit 2 of LCDC: Sprite size (8x16 or 8x8)

        // ponytail: no 10-sprites-per-line limit and no X-coordinate priority. Earlier OAM
        // entries simply win, which is what drawing them last achieves.
        for i in (0..<40).reversed() { // Maximum of 40 sprites
            let spriteAddr = 0xFE00 + i * 4 // Each sprite uses 4 bytes in OAM
            let yPos = Int(addressBus[spriteAddr]) - 16 // Y position is always offset by 16, even for 8x8 sprites
            let xPos = Int(addressBus[spriteAddr + 1]) - 8 // X position of the sprite (offset by 8)
            var tileIndex = Int(addressBus[spriteAddr + 2]) // Tile index
            let attributes = addressBus[spriteAddr + 3] // Sprite attributes

            guard ly >= yPos && ly < yPos + spriteHeight else {
                continue // The current scanline doesn't intersect with the sprite
            }

            // Bit 6 of attributes: Vertical flip
            let lineInTile = (attributes & 0x40 != 0) ? spriteHeight - 1 - (ly - yPos) : ly - yPos
            if spriteHeight == 16 {
                tileIndex &= 0xFE // A tall sprite is two consecutive tiles starting at an even index
            }
            let tileAddr = 0x8000 + tileIndex * 16 // Each tile is 16 bytes
            let data1 = addressBus[tileAddr + lineInTile * 2] // Tile data for the current line
            let data2 = addressBus[tileAddr + lineInTile * 2 + 1]

            for x in 0..<8 {
                // Bit 5 of attributes: Horizontal flip
                let colorBit = (attributes & 0x20 != 0) ? x : 7 - x
                let colorNum = ((data2 >> colorBit) & 1) << 1 | ((data1 >> colorBit) & 1) // Calculate color number (2 bits)
                let xPixel = xPos + x

                guard colorNum != 0, (0..<displayBufferWidth).contains(xPixel) else {
                    continue // Color number 0 is transparent
                }

                // Bit 7 of attributes: the sprite hides behind background colors 1-3
                if attributes & 0x80 != 0 && lineColorNumbers[xPixel] != 0 {
                    continue
                }

                // Bit 4 of attributes: Palette number
                let paletteAddr = attributes & 0x10 != 0 ? 0xFF49 : 0xFF48
                displayBuffer[ly * displayBufferWidth + xPixel] = getColor(colorNum: colorNum, paletteAddr: paletteAddr)
            }
        }
    }
}
