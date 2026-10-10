//
//  GameCatalogue.swift
//  GameBoyEmu
//

import Foundation

/// The proper names of well-known Game Boy and Game Boy Color games.
///
/// Every cartridge carries a title in its header (0x0134-0x0143), but it is at most 16
/// upper-case characters and often abbreviated: "MARIOLAND2", "KIRBY2", "ZELDA". This
/// catalogue maps those header titles to the names the games were sold under.
enum GameCatalogue {
    /// Looks up a game's proper name.
    ///
    /// - Parameters:
    ///   - headerTitle: The title from the cartridge header, as stored.
    ///   - isColor: Whether the header marks the game as made for the Game Boy Color.
    /// - Returns: The game's name, or `nil` if the catalogue doesn't know the game.
    static func name(headerTitle: String, isColor: Bool) -> String? {
        if isColor {
            // Color-era headers keep the title to 11 characters and follow it with a
            // 4-character product code, so "POKEMON_GLD" is stored as "POKEMON_GLDAAUE"
            let shortTitle = String(headerTitle.prefix(11)).trimmingCharacters(in: .whitespaces)
            if let name = colorNames[headerTitle] ?? colorNames[shortTitle] {
                return name
            }
        }
        return names[headerTitle]
    }

    /// Names for Game Boy Color games, and for Color re-releases that kept the header
    /// title of the original.
    private static let colorNames: [String: String] = [
        "POKEMON_GLD": "Pokémon Gold",
        "POKEMON_SLV": "Pokémon Silver",
        "PM_CRYSTAL": "Pokémon Crystal",
        "POKEPINBALL": "Pokémon Pinball",
        "POKECARD": "Pokémon Trading Card Game",
        "ZELDA": "The Legend of Zelda: Link's Awakening DX",
        "ZELDA NAYRU": "The Legend of Zelda: Oracle of Ages",
        "ZELDA DIN": "The Legend of Zelda: Oracle of Seasons",
        "WARIOLAND3": "Wario Land 3",
        "TETRIS DX": "Tetris DX",
    ]

    private static let names: [String: String] = [
        // Pokémon
        "POKEMON RED": "Pokémon Red",
        "POKEMON BLUE": "Pokémon Blue",
        "POKEMON GREEN": "Pokémon Green",
        "POKEMON YELLOW": "Pokémon Yellow",

        // Mario and Wario
        "SUPER MARIOLAND": "Super Mario Land",
        "MARIOLAND2": "Super Mario Land 2: 6 Golden Coins",
        "SUPERMARIOLAND3": "Wario Land: Super Mario Land 3",
        "WARIOLAND2": "Wario Land II",
        "WARIO BLAST": "Wario Blast: Featuring Bomberman!",
        "DR.MARIO": "Dr. Mario",
        "MARIO & YOSHI": "Mario & Yoshi",
        "YOSHI'S COOKIE": "Yoshi's Cookie",
        "MARIO'S PICROSS": "Mario's Picross",

        // Zelda, Kirby, Metroid, Kid Icarus
        "ZELDA": "The Legend of Zelda: Link's Awakening",
        "KIRBY DREAM LAND": "Kirby's Dream Land",
        "KIRBY2": "Kirby's Dream Land 2",
        "KIRBY'S PINBALL": "Kirby's Pinball Land",
        "KIRBY BLOCKBALL": "Kirby's Block Ball",
        "METROID2": "Metroid II: Return of Samus",
        "KID ICARUS": "Kid Icarus: Of Myths and Monsters",

        // Donkey Kong
        "DONKEY KONG": "Donkey Kong",
        "DONKEYKONGLAND": "Donkey Kong Land",
        "DONKEYKONGLAND 2": "Donkey Kong Land 2",
        "DONKEYKONGLAND 3": "Donkey Kong Land III",

        // Puzzle
        "TETRIS": "Tetris",
        "TETRIS2": "Tetris 2",
        "TETRIS ATTACK": "Tetris Attack",
        "QIX": "Qix",

        // Sports and racing
        "GOLF": "Golf",
        "TENNIS": "Tennis",
        "BASEBALL": "Baseball",
        "F1RACE": "F-1 Race",
        "WAVERACE": "Wave Race",

        // Action and arcade
        "ALLEY WAY": "Alleyway",
        "RADARMISSION": "Radar Mission",
        "SOLARSTRIKER": "Solar Striker",
        "BALLOON KID": "Balloon Kid",
        "SPACE INVADERS": "Space Invaders",
        "G&W GALLERY": "Game & Watch Gallery",
        "KILLERINSTINCT95": "Killer Instinct",
        "MEGAMAN": "Mega Man: Dr. Wily's Revenge",
        "STREET FIGHTER 2": "Street Fighter II",
        "MYSTIC QUEST": "Mystic Quest",
    ]
}
