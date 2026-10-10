import Foundation
import Testing
@testable import GameBoyEmu

@Test func catalogueNamesWellKnownGamesFromTheirHeaderTitles() throws {
    #expect(GameCatalogue.name(headerTitle: "POKEMON RED", isColor: false) == "Pokémon Red")
    #expect(GameCatalogue.name(headerTitle: "MARIOLAND2", isColor: false) == "Super Mario Land 2: 6 Golden Coins")

    // Color-era headers run the title and the product code together
    #expect(GameCatalogue.name(headerTitle: "POKEMON_GLDAAUE", isColor: true) == "Pokémon Gold")

    // The Color re-release of Link's Awakening kept the original's header title
    #expect(GameCatalogue.name(headerTitle: "ZELDA", isColor: false) == "The Legend of Zelda: Link's Awakening")
    #expect(GameCatalogue.name(headerTitle: "ZELDA", isColor: true) == "The Legend of Zelda: Link's Awakening DX")

    #expect(GameCatalogue.name(headerTitle: "SOME HOMEBREW", isColor: false) == nil)
}
