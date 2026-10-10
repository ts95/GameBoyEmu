//
//  CompatibilityPalettes.swift
//  GameBoyEmu
//

import Foundation

/// The colors a Game Boy Color gives to games made for the original Game Boy.
///
/// An original game only knows four shades. When one is inserted into a Game Boy Color, the
/// console's boot program picks three palettes of four colors for it: one for the background
/// and one for each of the two sprite palettes. The game still asks for "shade 0-3", and each
/// shade is shown as a color from the palette that applies.
///
/// The choice is automatic. The boot program adds up the 16 bytes of the game's title, looks
/// the sum up in a list of games Nintendo picked colors for, and where two games have the same
/// sum it tells them apart by the fourth letter of the title. Games that aren't published by
/// Nintendo, or aren't in the list, get the first combination.
///
/// The tables hold the values from the Game Boy Color's boot program, as documented in
/// SameBoy's boot ROM source (https://github.com/LIJI32/SameBoy, Expat license).
enum CompatibilityPalettes {
    private struct Entry {
        let titleChecksum: UInt8
        /// Index into `combinations`.
        let combination: Int
        /// Set for the games that share their checksum with another one.
        var fourthLetter: Character?
    }

    /// For each layer, the index into `colors` of the first of its four colors.
    private struct Combination {
        let object0: Int
        let object1: Int
        let background: Int
    }

    /// Picks the palettes for a cartridge.
    ///
    /// - Parameter rom: The cartridge ROM, including its header.
    /// - Returns: Four 15-bit colors (red in the low bits) for each layer, indexed by shade.
    static func palettes(forROM rom: [UInt8]) -> (background: [UInt16], object0: [UInt16], object1: [UInt16]) {
        let combination = combinations[combinationIndex(forROM: rom)]

        func palette(at start: Int) -> [UInt16] {
            Array(colors[start..<start + 4])
        }
        return (palette(at: combination.background), palette(at: combination.object0), palette(at: combination.object1))
    }

    private static func combinationIndex(forROM rom: [UInt8]) -> Int {
        guard rom.count >= 0x150 else {
            return 0
        }

        // Only games published by Nintendo are looked up. The publisher is the "old licensee
        // code", unless that says 0x33, in which case it is the two-character new one.
        let isNintendo = rom[0x14B] == 0x33
            ? rom[0x144] == UInt8(ascii: "0") && rom[0x145] == UInt8(ascii: "1")
            : rom[0x14B] == 0x01
        guard isNintendo else {
            return 0
        }

        let titleChecksum = rom[0x134...0x143].reduce(0, &+)
        let fourthLetter = Character(UnicodeScalar(rom[0x137]))

        let entry = entries.first {
            $0.titleChecksum == titleChecksum && ($0.fourthLetter == nil || $0.fourthLetter == fourthLetter)
        }
        return entry?.combination ?? 0
    }

    private static let entries: [Entry] = [
        Entry(titleChecksum: 0x00, combination: 0), // Default
        Entry(titleChecksum: 0x88, combination: 4), // ALLEY WAY
        Entry(titleChecksum: 0x16, combination: 5), // YAKUMAN
        Entry(titleChecksum: 0x36, combination: 35), // BASEBALL, (Game and Watch 2)
        Entry(titleChecksum: 0xD1, combination: 34), // TENNIS
        Entry(titleChecksum: 0xDB, combination: 3), // TETRIS
        Entry(titleChecksum: 0xF2, combination: 31), // QIX
        Entry(titleChecksum: 0x3C, combination: 15), // DR.MARIO
        Entry(titleChecksum: 0x8C, combination: 10), // RADARMISSION
        Entry(titleChecksum: 0x92, combination: 5), // F1RACE
        Entry(titleChecksum: 0x3D, combination: 19), // YOSSY NO TAMAGO
        Entry(titleChecksum: 0x5C, combination: 36),
        Entry(titleChecksum: 0x58, combination: 7), // X
        Entry(titleChecksum: 0xC9, combination: 37), // MARIOLAND2
        Entry(titleChecksum: 0x3E, combination: 30), // YOSSY NO COOKIE
        Entry(titleChecksum: 0x70, combination: 44), // ZELDA
        Entry(titleChecksum: 0x1D, combination: 21),
        Entry(titleChecksum: 0x59, combination: 32),
        Entry(titleChecksum: 0x69, combination: 31), // TETRIS FLASH
        Entry(titleChecksum: 0x19, combination: 20), // DONKEY KONG
        Entry(titleChecksum: 0x35, combination: 5), // MARIO'S PICROSS
        Entry(titleChecksum: 0xA8, combination: 33),
        Entry(titleChecksum: 0x14, combination: 13), // POKEMON RED, (GAMEBOYCAMERA G)
        Entry(titleChecksum: 0xAA, combination: 14), // POKEMON GREEN
        Entry(titleChecksum: 0x75, combination: 5), // PICROSS 2
        Entry(titleChecksum: 0x95, combination: 29), // YOSSY NO PANEPON
        Entry(titleChecksum: 0x99, combination: 5), // KIRAKIRA KIDS
        Entry(titleChecksum: 0x34, combination: 18), // GAMEBOY GALLERY
        Entry(titleChecksum: 0x6F, combination: 9), // POCKETCAMERA
        Entry(titleChecksum: 0x15, combination: 3),
        Entry(titleChecksum: 0xFF, combination: 2), // BALLOON KID
        Entry(titleChecksum: 0x97, combination: 26), // KINGOFTHEZOO
        Entry(titleChecksum: 0x4B, combination: 25), // DMG FOOTBALL
        Entry(titleChecksum: 0x90, combination: 25), // WORLD CUP
        Entry(titleChecksum: 0x17, combination: 41), // OTHELLO
        Entry(titleChecksum: 0x10, combination: 42), // SUPER RC PRO-AM
        Entry(titleChecksum: 0x39, combination: 26), // DYNABLASTER
        Entry(titleChecksum: 0xF7, combination: 45), // BOY AND BLOB GB2
        Entry(titleChecksum: 0xF6, combination: 42), // MEGAMAN
        Entry(titleChecksum: 0xA2, combination: 45), // STAR WARS-NOA
        Entry(titleChecksum: 0x49, combination: 36),
        Entry(titleChecksum: 0x4E, combination: 38), // WAVERACE
        Entry(titleChecksum: 0x43, combination: 26),
        Entry(titleChecksum: 0x68, combination: 42), // LOLO2
        Entry(titleChecksum: 0xE0, combination: 30), // YOSHI'S COOKIE
        Entry(titleChecksum: 0x8B, combination: 41), // MYSTIC QUEST
        Entry(titleChecksum: 0xF0, combination: 34),
        Entry(titleChecksum: 0xCE, combination: 34), // TOPRANKINGTENNIS
        Entry(titleChecksum: 0x0C, combination: 5), // MANSELL
        Entry(titleChecksum: 0x29, combination: 42), // MEGAMAN3
        Entry(titleChecksum: 0xE8, combination: 6), // SPACE INVADERS
        Entry(titleChecksum: 0xB7, combination: 5), // GAME&WATCH
        Entry(titleChecksum: 0x86, combination: 33), // DONKEYKONGLAND95
        Entry(titleChecksum: 0x9A, combination: 25), // ASTEROIDS/MISCMD
        Entry(titleChecksum: 0x52, combination: 42), // STREET FIGHTER 2
        Entry(titleChecksum: 0x01, combination: 42), // DEFENDER/JOUST
        Entry(titleChecksum: 0x9D, combination: 40), // KILLERINSTINCT95
        Entry(titleChecksum: 0x71, combination: 2), // TETRIS BLAST
        Entry(titleChecksum: 0x9C, combination: 16), // PINOCCHIO
        Entry(titleChecksum: 0xBD, combination: 25),
        Entry(titleChecksum: 0x5D, combination: 42), // BA.TOSHINDEN
        Entry(titleChecksum: 0x6D, combination: 42), // NETTOU KOF 95
        Entry(titleChecksum: 0x67, combination: 5),
        Entry(titleChecksum: 0x3F, combination: 0), // TETRIS PLUS
        Entry(titleChecksum: 0x6B, combination: 39), // DONKEYKONGLAND 3
        Entry(titleChecksum: 0xB3, combination: 36, fourthLetter: "B"),
        Entry(titleChecksum: 0x46, combination: 22, fourthLetter: "E"), // SUP[E]R MARIOLAND
        Entry(titleChecksum: 0x28, combination: 25, fourthLetter: "F"), // GOL[F]
        Entry(titleChecksum: 0xA5, combination: 6, fourthLetter: "A"), // SOL[A]RSTRIKER
        Entry(titleChecksum: 0xC6, combination: 32, fourthLetter: "A"), // GBW[A]RS
        Entry(titleChecksum: 0xD3, combination: 12, fourthLetter: "R"), // KAE[R]UNOTAMENI
        Entry(titleChecksum: 0x27, combination: 36, fourthLetter: "B"),
        Entry(titleChecksum: 0x61, combination: 11, fourthLetter: "E"), // POK[E]MON BLUE
        Entry(titleChecksum: 0x18, combination: 39, fourthLetter: "K"), // DON[K]EYKONGLAND
        Entry(titleChecksum: 0x66, combination: 18, fourthLetter: "E"), // GAM[E]BOY GALLERY2
        Entry(titleChecksum: 0x6A, combination: 39, fourthLetter: "K"), // DON[K]EYKONGLAND 2
        Entry(titleChecksum: 0xBF, combination: 24, fourthLetter: " "), // KID[ ]ICARUS
        Entry(titleChecksum: 0x0D, combination: 31, fourthLetter: "R"), // TET[R]IS2
        Entry(titleChecksum: 0xF4, combination: 50, fourthLetter: "-"),
        Entry(titleChecksum: 0xB3, combination: 17, fourthLetter: "U"), // MOG[U]RANYA
        Entry(titleChecksum: 0x46, combination: 46, fourthLetter: "R"),
        Entry(titleChecksum: 0x28, combination: 6, fourthLetter: "A"), // GAL[A]GA&GALAXIAN
        Entry(titleChecksum: 0xA5, combination: 27, fourthLetter: "R"), // BT2[R]AGNAROKWORLD
        Entry(titleChecksum: 0xC6, combination: 0, fourthLetter: " "), // KEN[ ]GRIFFEY JR
        Entry(titleChecksum: 0xD3, combination: 47, fourthLetter: "I"),
        Entry(titleChecksum: 0x27, combination: 41, fourthLetter: "N"), // MAG[N]ETIC SOCCER
        Entry(titleChecksum: 0x61, combination: 41, fourthLetter: "A"), // VEG[A]S STAKES
        Entry(titleChecksum: 0x18, combination: 0, fourthLetter: "I"),
        Entry(titleChecksum: 0x66, combination: 0, fourthLetter: "L"), // MIL[L]I/CENTI/PEDE
        Entry(titleChecksum: 0x6A, combination: 19, fourthLetter: "I"), // MAR[I]O & YOSHI
        Entry(titleChecksum: 0xBF, combination: 34, fourthLetter: "C"), // SOC[C]ER
        Entry(titleChecksum: 0x0D, combination: 23, fourthLetter: "E"), // POK[E]BOM
        Entry(titleChecksum: 0xF4, combination: 18, fourthLetter: " "), // G&W[ ]GALLERY
        Entry(titleChecksum: 0xB3, combination: 29, fourthLetter: "R"), // TET[R]IS ATTACK
    ]

    private static let combinations: [Combination] = [
        Combination(object0: 16, object1: 16, background: 116), // 0
        Combination(object0: 72, object1: 72, background: 72), // 1
        Combination(object0: 80, object1: 80, background: 80), // 2
        Combination(object0: 96, object1: 96, background: 96), // 3
        Combination(object0: 36, object1: 36, background: 36), // 4
        Combination(object0: 0, object1: 0, background: 0), // 5
        Combination(object0: 108, object1: 108, background: 108), // 6
        Combination(object0: 20, object1: 20, background: 20), // 7
        Combination(object0: 48, object1: 48, background: 48), // 8
        Combination(object0: 104, object1: 104, background: 104), // 9
        Combination(object0: 64, object1: 32, background: 32), // 10
        Combination(object0: 16, object1: 112, background: 112), // 11
        Combination(object0: 16, object1: 8, background: 8), // 12
        Combination(object0: 12, object1: 16, background: 16), // 13
        Combination(object0: 16, object1: 116, background: 116), // 14
        Combination(object0: 112, object1: 16, background: 112), // 15
        Combination(object0: 8, object1: 68, background: 8), // 16
        Combination(object0: 64, object1: 64, background: 32), // 17
        Combination(object0: 16, object1: 16, background: 28), // 18
        Combination(object0: 16, object1: 16, background: 72), // 19
        Combination(object0: 16, object1: 16, background: 80), // 20
        Combination(object0: 76, object1: 76, background: 36), // 21
        Combination(object0: 15, object1: 15, background: 44), // 22
        Combination(object0: 68, object1: 68, background: 8), // 23
        Combination(object0: 16, object1: 16, background: 8), // 24
        Combination(object0: 16, object1: 16, background: 12), // 25
        Combination(object0: 112, object1: 112, background: 0), // 26
        Combination(object0: 12, object1: 12, background: 0), // 27
        Combination(object0: 0, object1: 0, background: 4), // 28
        Combination(object0: 72, object1: 88, background: 72), // 29
        Combination(object0: 80, object1: 88, background: 80), // 30
        Combination(object0: 96, object1: 88, background: 96), // 31
        Combination(object0: 64, object1: 88, background: 32), // 32
        Combination(object0: 68, object1: 16, background: 52), // 33
        Combination(object0: 111, object1: 0, background: 56), // 34
        Combination(object0: 111, object1: 16, background: 60), // 35
        Combination(object0: 76, object1: 91, background: 36), // 36
        Combination(object0: 64, object1: 112, background: 40), // 37
        Combination(object0: 16, object1: 92, background: 112), // 38
        Combination(object0: 68, object1: 88, background: 8), // 39
        Combination(object0: 16, object1: 0, background: 8), // 40
        Combination(object0: 16, object1: 112, background: 12), // 41
        Combination(object0: 112, object1: 12, background: 0), // 42
        Combination(object0: 12, object1: 112, background: 16), // 43
        Combination(object0: 84, object1: 112, background: 16), // 44
        Combination(object0: 12, object1: 112, background: 0), // 45
        Combination(object0: 100, object1: 12, background: 112), // 46
        Combination(object0: 0, object1: 112, background: 32), // 47
        Combination(object0: 16, object1: 12, background: 112), // 48
        Combination(object0: 112, object1: 12, background: 24), // 49
        Combination(object0: 16, object1: 112, background: 116), // 50
    ]

    /// 30 palettes of four colors each, although a few combinations start in the middle of one.
    private static let colors: [UInt16] = [
        0x7FFF, 0x32BF, 0x00D0, 0x0000,
        0x639F, 0x4279, 0x15B0, 0x04CB,
        0x7FFF, 0x6E31, 0x454A, 0x0000,
        0x7FFF, 0x1BEF, 0x0200, 0x0000,
        0x7FFF, 0x421F, 0x1CF2, 0x0000,
        0x7FFF, 0x5294, 0x294A, 0x0000,
        0x7FFF, 0x03FF, 0x012F, 0x0000,
        0x7FFF, 0x03EF, 0x01D6, 0x0000,
        0x7FFF, 0x42B5, 0x3DC8, 0x0000,
        0x7E74, 0x03FF, 0x0180, 0x0000,
        0x67FF, 0x77AC, 0x1A13, 0x2D6B,
        0x7ED6, 0x4BFF, 0x2175, 0x0000,
        0x53FF, 0x4A5F, 0x7E52, 0x0000,
        0x4FFF, 0x7ED2, 0x3A4C, 0x1CE0,
        0x03ED, 0x7FFF, 0x255F, 0x0000,
        0x036A, 0x021F, 0x03FF, 0x7FFF,
        0x7FFF, 0x01DF, 0x0112, 0x0000,
        0x231F, 0x035F, 0x00F2, 0x0009,
        0x7FFF, 0x03EA, 0x011F, 0x0000,
        0x299F, 0x001A, 0x000C, 0x0000,
        0x7FFF, 0x027F, 0x001F, 0x0000,
        0x7FFF, 0x03E0, 0x0206, 0x0120,
        0x7FFF, 0x7EEB, 0x001F, 0x7C00,
        0x7FFF, 0x3FFF, 0x7E00, 0x001F,
        0x7FFF, 0x03FF, 0x001F, 0x0000,
        0x03FF, 0x001F, 0x000C, 0x0000,
        0x7FFF, 0x033F, 0x0193, 0x0000,
        0x0000, 0x4200, 0x037F, 0x7FFF,
        0x7FFF, 0x7E8C, 0x7C00, 0x0000,
        0x7FFF, 0x1BEF, 0x6180, 0x0000,
    ]
}
