//
//  GameBoyPPU.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 03/07/2024.
//

import Foundation

let displayBufferWidth = 160
let displayBufferHeight = 144

/// A white display buffer pixel, which is what the screen shows before anything is drawn.
let blankPixel: UInt32 = 0xFFFF_FFFF

/// Converts a Game Boy Color color (15 bits: 5 each of red, green and blue, red lowest)
/// into a display buffer pixel.
///
/// ponytail: the 5-bit channels are stretched straight to 8 bits. The real LCD is more
/// washed out; add a color correction curve here if the colors look too saturated.
func displayPixel(from color: UInt16) -> UInt32 {
    func channel(_ shift: UInt16) -> UInt32 {
        let value = UInt32((color >> shift) & 0x1F)
        return value << 3 | value >> 2
    }
    return 0xFF00_0000 | channel(10) << 16 | channel(5) << 8 | channel(0)
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
    /// A pixel is a ready-to-show color: its bytes in memory are red, green, blue and an unused
    /// fourth byte.
    var displayBuffer: [UInt32] = Array(repeating: blankPixel, count: displayBufferWidth * displayBufferHeight)

    /// The background/window color numbers (before the palette) of the scanline being drawn.
    /// Sprites need them, because a sprite can ask to be drawn behind non-zero background pixels.
    private var lineColorNumbers: [UInt8] = Array(repeating: 0, count: displayBufferWidth)

    /// Whether each background/window pixel of the scanline comes from a tile that asks to be
    /// drawn in front of all sprites (Game Boy Color only).
    private var lineHasPriority: [Bool] = Array(repeating: false, count: displayBufferWidth)

    /// How many window lines have been drawn this frame. The window keeps its own line counter,
    /// it does not simply follow the scanline number.
    private var windowLine = 0

    init(addressBus: AddressBus) {
        self.addressBus = addressBus
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
                addressBus.horizontalBlankDidStart()
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

    /// Turns a color number (0-3) into a display buffer pixel for an original Game Boy game.
    ///
    /// The game's palette register maps each color number to one of four shades, two bits
    /// each: bits 1-0 for color number 0, up to bits 7-6 for color number 3. On an original
    /// Game Boy that shade was the final result. A Game Boy Color goes one step further and
    /// shows each shade as a color from a palette it chose for the game (see
    /// `CompatibilityPalettes`), which is what happens here.
    ///
    /// - Parameters:
    ///   - colorNum: The 2-bit color number (0 to 3) for the pixel.
    ///   - paletteAddr: The address of the game's palette register in addressBus.
    ///   - palette: Which of the console's color palettes the shades are shown with.
    ///   - isObject: Whether that is a sprite palette or a background palette.
    private func compatibilityColor(colorNum: UInt8, paletteAddr: Int, palette: Int, isObject: Bool) -> UInt32 {
        let shade = (addressBus[paletteAddr] >> (colorNum * 2)) & 0x03
        return color(colorNum: shade, palette: palette, isObject: isObject)
    }

    /// Looks a color number (0-3) up in one of the console's color palettes.
    ///
    /// There are 8 background and 8 sprite palettes of 4 colors each, and on a Game Boy Color
    /// every tile or sprite says which one it uses.
    private func color(colorNum: UInt8, palette: Int, isObject: Bool) -> UInt32 {
        displayPixel(from: addressBus.colorPaletteEntry(isObject: isObject, index: palette * 4 + Int(colorNum)))
    }

    private func renderScanline() {
        // Render the current scanline to the display buffer
        let lcdc = addressBus[0xFF40] // LCD Control register
        let ly = Int(currentScanline) // Current scanline
        let isColorMode = addressBus.isColorMode

        // Bit 0 of LCDC switches the background and window off on an original Game Boy.
        // On a Game Boy Color they are always drawn, and the bit instead decides whether
        // they can ever cover a sprite.
        let bgEnabled = isColorMode || lcdc & 0x01 != 0
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
            var pixel: (colorNumber: UInt8, attributes: UInt8) = (0, 0)
            if isWindowVisible && x >= windowX {
                pixel = tilePixel(tileMapBase: windowTileMapBase, x: x - windowX, y: windowLine)
            } else if bgEnabled {
                // The background is a 256x256 pixel map that wraps around; SCX/SCY pick which
                // part of it is visible through the 160x144 screen.
                pixel = tilePixel(tileMapBase: bgTileMapBase, x: (x + scx) % 256, y: (ly + scy) % 256)
            }

            lineColorNumbers[x] = pixel.colorNumber
            lineHasPriority[x] = pixel.attributes & 0x80 != 0 // Bit 7 of the tile attributes
            displayBuffer[ly * displayBufferWidth + x] = isColorMode
                ? color(colorNum: pixel.colorNumber, palette: Int(pixel.attributes & 0x07), isObject: false)
                : compatibilityColor(colorNum: pixel.colorNumber, paletteAddr: 0xFF47, palette: 0, isObject: false)
        }

        if isWindowVisible {
            windowLine += 1
        }

        // Render sprites
        if spritesEnabled {
            renderSpritesLine(ly: ly)
        }
    }

    /// Looks up one pixel of a 256x256 tile map.
    ///
    /// A tile map doesn't contain pixels. It is a 32x32 grid of tile numbers, and each tile
    /// number refers to an 8x8 pixel picture stored elsewhere in VRAM (2 bytes per row of pixels).
    ///
    /// On a Game Boy Color, VRAM bank 1 holds an attribute byte for every entry of the grid:
    /// bits 0-2 pick the palette, bit 3 the VRAM bank the picture is in, bits 5 and 6 flip
    /// it, and bit 7 puts it in front of sprites.
    ///
    /// - Parameters:
    ///   - tileMapBase: The address of the tile map, 0x9800 or 0x9C00.
    ///   - x: The horizontal pixel position in the map.
    ///   - y: The vertical pixel position in the map.
    /// - Returns: The pixel's color number (0-3) and its tile's attributes (0 on an original Game Boy).
    private func tilePixel(tileMapBase: Int, x: Int, y: Int) -> (colorNumber: UInt8, attributes: UInt8) {
        let mapAddr = tileMapBase + (y / 8) * 32 + x / 8 // 32 tiles per row
        let tileIndex = addressBus.videoRAM(bank: 0, address: mapAddr)
        let attributes = addressBus.isColorMode ? addressBus.videoRAM(bank: 1, address: mapAddr) : 0

        let tileAddr: Int
        if addressBus[0xFF40] & 0x10 != 0 { // Bit 4 of LCDC: Background & window tile data select
            tileAddr = 0x8000 + Int(tileIndex) * 16 // Each tile is 16 bytes
        } else {
            tileAddr = 0x9000 + Int(Int8(bitPattern: tileIndex)) * 16 // Signed tile index around 0x9000
        }

        let bank = Int(attributes >> 3) & 1
        let lineInTile = attributes & 0x40 != 0 ? 7 - y % 8 : y % 8 // Bit 6: vertical flip
        let data1 = addressBus.videoRAM(bank: bank, address: tileAddr + lineInTile * 2) // Tile data for the current line
        let data2 = addressBus.videoRAM(bank: bank, address: tileAddr + lineInTile * 2 + 1)

        // The leftmost pixel is stored in bit 7. Bit 5 of the attributes: horizontal flip
        let colorBit = attributes & 0x20 != 0 ? x % 8 : 7 - x % 8
        return (((data2 >> colorBit) & 1) << 1 | ((data1 >> colorBit) & 1), attributes)
    }

    /// Renders the sprites for the given scanline (ly).
    ///
    /// - Parameter ly: The current scanline.
    private func renderSpritesLine(ly: Int) {
        let lcdc = addressBus[0xFF40] // LCD Control register
        let spriteHeight = (lcdc & 0x04 != 0) ? 16 : 8 // Bit 2 of LCDC: Sprite size (8x16 or 8x8)
        let isColorMode = addressBus.isColorMode

        // ponytail: no 10-sprites-per-line limit, and on an original Game Boy no X-coordinate
        // priority. Earlier OAM entries simply win, which is what drawing them last achieves
        // (and is the actual rule on a Game Boy Color).
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
            let bank = isColorMode ? Int(attributes >> 3) & 1 : 0 // Bit 3 of attributes: VRAM bank (Color only)
            let data1 = addressBus.videoRAM(bank: bank, address: tileAddr + lineInTile * 2) // Tile data for the current line
            let data2 = addressBus.videoRAM(bank: bank, address: tileAddr + lineInTile * 2 + 1)

            for x in 0..<8 {
                // Bit 5 of attributes: Horizontal flip
                let colorBit = (attributes & 0x20 != 0) ? x : 7 - x
                let colorNum = ((data2 >> colorBit) & 1) << 1 | ((data1 >> colorBit) & 1) // Calculate color number (2 bits)
                let xPixel = xPos + x

                guard colorNum != 0, (0..<displayBufferWidth).contains(xPixel) else {
                    continue // Color number 0 is transparent
                }

                // A sprite hides behind background colors 1-3 when it asks to (bit 7 of its
                // attributes) or, on a Game Boy Color, when the background tile asks to be in
                // front. Clearing bit 0 of LCDC on a Color puts sprites on top regardless.
                let isBehindBackground = isColorMode
                    ? lcdc & 0x01 != 0 && (attributes & 0x80 != 0 || lineHasPriority[xPixel])
                    : attributes & 0x80 != 0
                if isBehindBackground && lineColorNumbers[xPixel] != 0 {
                    continue
                }

                displayBuffer[ly * displayBufferWidth + xPixel] = isColorMode
                    // Bits 0-2 of attributes: Color palette number
                    ? color(colorNum: colorNum, palette: Int(attributes & 0x07), isObject: true)
                    // Bit 4 of attributes: which of the two original sprite palettes
                    : attributes & 0x10 != 0
                        ? compatibilityColor(colorNum: colorNum, paletteAddr: 0xFF49, palette: 1, isObject: true)
                        : compatibilityColor(colorNum: colorNum, paletteAddr: 0xFF48, palette: 0, isObject: true)
            }
        }
    }
}
