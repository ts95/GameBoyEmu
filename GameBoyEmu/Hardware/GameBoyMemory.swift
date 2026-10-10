//
//  GameBoyMemory.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 03/07/2024.
//

import Foundation

private let ROM_BANK_0_START: Int = 0x0000
private let ROM_BANK_0_END: Int = 0x3FFF
private let ROM_BANK_1_START: Int = 0x4000
private let ROM_BANK_1_END: Int = 0x7FFF
private let VRAM_START: Int = 0x8000
private let VRAM_END: Int = 0x9FFF
private let EXTERNAL_RAM_START: Int = 0xA000
private let EXTERNAL_RAM_END: Int = 0xBFFF
private let WRAM_START: Int = 0xC000
private let WRAM_END: Int = 0xDFFF
private let ECHO_RAM_START: Int = 0xE000
private let ECHO_RAM_END: Int = 0xFDFF
private let OAM_START: Int = 0xFE00
private let OAM_END: Int = 0xFE9F
private let IO_PORTS_START: Int = 0xFF00
private let IO_PORTS_END: Int = 0xFF7F
private let HRAM_START: Int = 0xFF80
private let HRAM_END: Int = 0xFFFE
private let INTERRUPT_ENABLE_REGISTER: Int = 0xFFFF

private let MBC_ROM_BANK_NUMBER_START: Int = 0x2000
private let MBC_ROM_BANK_NUMBER_END: Int = 0x3FFF
private let MBC_RAM_BANK_NUMBER_START: Int = 0x4000
private let MBC_RAM_BANK_NUMBER_END: Int = 0x5FFF
private let MBC_BANKING_MODE_START: Int = 0x6000
private let MBC_BANKING_MODE_END: Int = 0x7FFF

private let JOYPAD_REGISTER: Int = 0xFF00
private let SERIAL_DATA_REGISTER: Int = 0xFF01
private let SERIAL_CONTROL_REGISTER: Int = 0xFF02
private let TIMER_REGISTERS_START: Int = 0xFF04
private let TIMER_REGISTERS_END: Int = 0xFF07
private let INTERRUPT_FLAG_REGISTER: Int = 0xFF0F
private let SOUND_REGISTERS_START: Int = 0xFF10
private let SOUND_REGISTERS_END: Int = 0xFF3F
private let DMA_REGISTER: Int = 0xFF46

private let VRAM_BANK_REGISTER: Int = 0xFF4F
private let HDMA_SOURCE_HIGH_REGISTER: Int = 0xFF51
private let HDMA_SOURCE_LOW_REGISTER: Int = 0xFF52
private let HDMA_DESTINATION_HIGH_REGISTER: Int = 0xFF53
private let HDMA_DESTINATION_LOW_REGISTER: Int = 0xFF54
private let HDMA_CONTROL_REGISTER: Int = 0xFF55
private let BACKGROUND_PALETTE_INDEX_REGISTER: Int = 0xFF68
private let BACKGROUND_PALETTE_DATA_REGISTER: Int = 0xFF69
private let OBJECT_PALETTE_INDEX_REGISTER: Int = 0xFF6A
private let OBJECT_PALETTE_DATA_REGISTER: Int = 0xFF6B
private let WRAM_BANK_REGISTER: Int = 0xFF70

private let BANK_SIZE = 0x4000
private let RAM_BANK_SIZE = 0x2000
private let VRAM_BANK_SIZE = 0x2000
private let WRAM_BANK_SIZE = 0x1000

enum BankingMode: UInt8 {
    case rom = 0
    case ram = 1
}

/// The address bus: everything the CPU can reach through a 16-bit address.
///
/// Only part of the address space is actual memory. 0x0000-0x7FFF is the cartridge ROM, which
/// can't be written to: writes there are instead picked up by the cartridge's bank controller
/// chip (MBC) as commands. 0xFF00-0xFF7F are hardware registers, where reads and writes talk
/// to the joypad, timer, PPU and so on rather than storing a byte.
class GameBoyMemory: AddressBusProtocol {

    // MARK: - CPU memory

    // External RAM: Optional RAM on the cartridge, often battery-backed for saving games.
    // At least 4 banks of 8KB; resized when a cartridge that has more is loaded.
    var externalRam: Array<UInt8>

    // Work RAM: General-purpose RAM used by the CPU for various tasks. 8 banks of 4KB:
    // bank 0 is always at 0xC000, and 0xD000 shows bank 1 or, on a Game Boy Color,
    // whichever of banks 1-7 the game has selected.
    var wram: Array<UInt8>
    var wramBank = 1

    // I/O Ports: Used for input/output operations and hardware control registers.
    var ioPorts: Array<UInt8>

    // High RAM: Fast RAM used for stack and immediate data storage.
    var hram: Array<UInt8>

    // IE: one bit per interrupt source, selecting which interrupts the game wants to receive.
    var interruptEnableReg: UInt8 = 0

    // MARK: - PPU memory

    // Video RAM: Used by the PPU for tile data and attributes. A Game Boy Color has two
    // banks of it: bank 1 holds more tiles, plus one attribute byte per background tile.
    var vram: Array<UInt8>
    var vramBank = 0

    /// Whether the machine runs as a Game Boy Color, which the cartridge header decides.
    /// An original Game Boy game runs exactly as it does on the original hardware.
    private(set) var isColorMode = false

    // Color palettes: 8 for the background and 8 for sprites, each with 4 colors of 2 bytes.
    // They aren't in the address space; the game writes them one byte at a time through an
    // index register and a data register.
    var backgroundPalettes = [UInt8](repeating: 0xFF, count: 64)
    var objectPalettes = [UInt8](repeating: 0xFF, count: 64)

    // HDMA: a Game Boy Color feature that copies data from ROM or RAM into video RAM.
    // The addresses advance as blocks of 16 bytes are copied.
    private var transferSource = 0
    private var transferDestination = 0
    private var transferBlocksRemaining = 0
    private var isHBlankTransferActive = false

    // Object Attribute Memory: Used by the PPU for sprite attributes.
    var oam: Array<UInt8>

    // MARK: - Hardware behind the I/O ports

    /// The DIV/TIMA timer, mapped at 0xFF04-0xFF07.
    let clock = GameBoyClock()

    /// The sound hardware, mapped at 0xFF10-0xFF3F.
    let apu = GameBoyAPU()

    /// The buttons, readable through 0xFF00.
    var joypad = JoypadState()

    /// Every byte the game has sent over the link cable. Test ROMs print their results this way.
    var serialOutput: [UInt8] = []

    // MARK: - Cartridge

    // All the ROM data of a Game Boy cartridge. The CPU only ever sees two 16KB windows of it:
    // bank 0 at 0x0000-0x3FFF and one switchable bank at 0x4000-0x7FFF.
    var cartridgeData: [UInt8] = []

    // Bank registers
    var bank1: UInt8 = 1 // ROM bank number (5 bits on MBC1, 7 bits on MBC3, low 8 bits on MBC5)
    var bank1High: UInt8 = 0 // Bit 8 of the ROM bank number (MBC5 only)
    var bank2: UInt8 = 0 // RAM bank number, or the upper ROM bank bits on MBC1
    var mode: BankingMode = .rom // Mode register (MBC1 only)

    /// The cartridge header says which bank controller chip the cartridge has.
    private var cartridgeType: UInt8 {
        cartridgeData.count > 0x147 ? cartridgeData[0x147] : 0
    }

    /// Whether the cartridge keeps its RAM powered with a battery, which is how games save.
    /// Without one the RAM is just extra scratch space that is lost at power-off.
    var hasBattery: Bool {
        [0x03, 0x06, 0x09, 0x0D, 0x0F, 0x10, 0x13, 0x1B, 0x1E].contains(cartridgeType)
    }

    /// Set whenever the game writes to cartridge RAM, so the host knows there is something
    /// new to write to the save file. The host clears it after saving.
    var hasUnsavedExternalRam = false

    private var isMBC3: Bool {
        (0x0F...0x13).contains(cartridgeType)
    }

    private var isMBC5: Bool {
        (0x19...0x1E).contains(cartridgeType)
    }

    private var romBankOffset: Int {
        let bank: Int
        if isMBC5 {
            bank = Int(bank1) | (Int(bank1High) << 8)
        } else if isMBC3 {
            bank = Int(bank1)
        } else {
            bank = Int(bank1) | (Int(bank2) << 5)
        }
        let bankCount = max(cartridgeData.count / BANK_SIZE, 2)
        return (bank % bankCount) * BANK_SIZE
    }

    private func externalRamIndex(_ address: Int) -> Int {
        let bank = isMBC5 || isMBC3 || mode == .ram ? Int(bank2) : 0
        return (bank * RAM_BANK_SIZE + address - EXTERNAL_RAM_START) % externalRam.count
    }

    /// 0xC000-0xCFFF is always bank 0 and 0xD000-0xDFFF the selected bank. Echo RAM
    /// (0xE000-0xFDFF) mirrors the same memory, which masking the address takes care of.
    private func wramIndex(_ address: Int) -> Int {
        let offset = address & 0x1FFF
        return offset < WRAM_BANK_SIZE ? offset : wramBank * WRAM_BANK_SIZE + offset - WRAM_BANK_SIZE
    }

    // MARK: - Initializer

    init() {
        externalRam = Array(repeating: 0, count: 4 * RAM_BANK_SIZE)
        wram = Array(repeating: 0, count: 8 * WRAM_BANK_SIZE)
        ioPorts = Array(repeating: 0, count: IO_PORTS_END - IO_PORTS_START + 1)
        hram = Array(repeating: 0, count: HRAM_END - HRAM_START + 1)
        vram = Array(repeating: 0, count: 2 * VRAM_BANK_SIZE)
        oam = Array(repeating: 0, count: OAM_END - OAM_START + 1)

        initializeHardware()
    }

    // Subscript to access memory using the 0x0000 to 0xFFFF address format
    subscript(address: Int) -> UInt8 {
        get {
            switch address {
            case ROM_BANK_0_START...ROM_BANK_0_END:
                return address < cartridgeData.count ? cartridgeData[address] : 0xFF
            case ROM_BANK_1_START...ROM_BANK_1_END:
                let index = romBankOffset + address - ROM_BANK_1_START
                return index < cartridgeData.count ? cartridgeData[index] : 0xFF
            case VRAM_START...VRAM_END:
                return vram[vramBank * VRAM_BANK_SIZE + address - VRAM_START]
            case EXTERNAL_RAM_START...EXTERNAL_RAM_END:
                // ponytail: MBC3 real-time clock registers (bank2 >= 8) read as ordinary RAM.
                // Add an RTC if a game's in-game clock matters.
                return externalRam[externalRamIndex(address)]
            case WRAM_START...ECHO_RAM_END:
                return wram[wramIndex(address)]
            case OAM_START...OAM_END:
                return oam[address - OAM_START]
            case JOYPAD_REGISTER:
                return readJoypad()
            case TIMER_REGISTERS_START...TIMER_REGISTERS_END:
                return clock[address]
            case INTERRUPT_FLAG_REGISTER:
                return ioPorts[address - IO_PORTS_START] | 0xE0 // The unused upper bits read as 1
            case SOUND_REGISTERS_START...SOUND_REGISTERS_END:
                return apu[address]
            case VRAM_BANK_REGISTER where isColorMode:
                return UInt8(vramBank) | 0xFE
            case WRAM_BANK_REGISTER where isColorMode:
                return UInt8(wramBank) | 0xF8
            case HDMA_CONTROL_REGISTER where isColorMode:
                // The blocks left, minus one. Bit 7 is clear while an HBlank transfer is running,
                // so 0xFF means "finished".
                let remaining = UInt8(truncatingIfNeeded: transferBlocksRemaining - 1)
                return isHBlankTransferActive ? remaining & 0x7F : remaining | 0x80
            case BACKGROUND_PALETTE_DATA_REGISTER where isColorMode:
                return backgroundPalettes[Int(ioPorts[BACKGROUND_PALETTE_INDEX_REGISTER - IO_PORTS_START] & 0x3F)]
            case OBJECT_PALETTE_DATA_REGISTER where isColorMode:
                return objectPalettes[Int(ioPorts[OBJECT_PALETTE_INDEX_REGISTER - IO_PORTS_START] & 0x3F)]
            case IO_PORTS_START...IO_PORTS_END:
                return ioPorts[address - IO_PORTS_START]
            case HRAM_START...HRAM_END:
                return hram[address - HRAM_START]
            case INTERRUPT_ENABLE_REGISTER:
                return interruptEnableReg
            default:
                // Out of bounds access returns 0
                return 0
            }
        }
        set {
            switch address {
            // The cartridge is read-only memory. Writing to its address range doesn't change
            // the ROM, it sends a command to the bank controller chip on the cartridge.
            case MBC_ROM_BANK_NUMBER_START...MBC_ROM_BANK_NUMBER_END:
                writeBank1(address: address, value: newValue)
            case MBC_RAM_BANK_NUMBER_START...MBC_RAM_BANK_NUMBER_END:
                bank2 = isMBC3 || isMBC5 ? newValue & 0x0F : newValue & 0x03
            case MBC_BANKING_MODE_START...MBC_BANKING_MODE_END:
                mode = BankingMode(rawValue: newValue & 0x01)!
            case ROM_BANK_0_START...ROM_BANK_1_END:
                // ponytail: 0x0000-0x1FFF is the external RAM enable switch. RAM is always
                // enabled here; honor it if a game depends on RAM being locked.
                break
            case VRAM_START...VRAM_END:
                vram[vramBank * VRAM_BANK_SIZE + address - VRAM_START] = newValue
            case EXTERNAL_RAM_START...EXTERNAL_RAM_END:
                externalRam[externalRamIndex(address)] = newValue
                hasUnsavedExternalRam = true
            case WRAM_START...ECHO_RAM_END:
                wram[wramIndex(address)] = newValue
            case OAM_START...OAM_END:
                oam[address - OAM_START] = newValue
            case JOYPAD_REGISTER:
                // Only the two "which half of the buttons do you want" bits are writable
                ioPorts[0] = newValue & 0x30
            case SERIAL_CONTROL_REGISTER:
                ioPorts[address - IO_PORTS_START] = newValue
                if newValue == 0x81 {
                    // ponytail: no link cable partner, the byte is just recorded. Raise the
                    // serial interrupt (IF bit 3) here if a game waits for the transfer to end.
                    serialOutput.append(self[SERIAL_DATA_REGISTER])
                }
            case TIMER_REGISTERS_START...TIMER_REGISTERS_END:
                clock[address] = newValue
            case SOUND_REGISTERS_START...SOUND_REGISTERS_END:
                apu[address] = newValue
            case DMA_REGISTER:
                // Writing XX here makes the hardware copy 0xXX00-0xXX9F into OAM. Games do this
                // every frame, it is how sprites get on screen.
                ioPorts[address - IO_PORTS_START] = newValue
                let source = Int(newValue) << 8
                for offset in 0..<oam.count {
                    oam[offset] = self[source + offset]
                }
            case VRAM_BANK_REGISTER where isColorMode:
                vramBank = Int(newValue & 0x01)
            case WRAM_BANK_REGISTER where isColorMode:
                wramBank = max(Int(newValue & 0x07), 1) // Selecting bank 0 gives bank 1
            case BACKGROUND_PALETTE_DATA_REGISTER where isColorMode:
                writePaletteData(newValue, to: &backgroundPalettes, indexRegister: BACKGROUND_PALETTE_INDEX_REGISTER)
            case OBJECT_PALETTE_DATA_REGISTER where isColorMode:
                writePaletteData(newValue, to: &objectPalettes, indexRegister: OBJECT_PALETTE_INDEX_REGISTER)
            case HDMA_SOURCE_HIGH_REGISTER where isColorMode:
                transferSource = (transferSource & 0x00FF) | Int(newValue) << 8
            case HDMA_SOURCE_LOW_REGISTER where isColorMode:
                transferSource = (transferSource & 0xFF00) | Int(newValue & 0xF0)
            case HDMA_DESTINATION_HIGH_REGISTER where isColorMode:
                transferDestination = (transferDestination & 0x00FF) | Int(newValue & 0x1F) << 8
            case HDMA_DESTINATION_LOW_REGISTER where isColorMode:
                transferDestination = (transferDestination & 0xFF00) | Int(newValue & 0xF0)
            case HDMA_CONTROL_REGISTER where isColorMode:
                writeTransferControl(newValue)
            case IO_PORTS_START...IO_PORTS_END:
                ioPorts[address - IO_PORTS_START] = newValue
            case HRAM_START...HRAM_END:
                hram[address - HRAM_START] = newValue
            case INTERRUPT_ENABLE_REGISTER:
                interruptEnableReg = newValue
            default:
                // Ignore writes to out of bounds addresses
                break
            }
        }
    }

    /// Inserts a cartridge.
    ///
    /// - Parameters:
    ///   - data: The cartridge ROM.
    ///   - save: The contents of the cartridge RAM from an earlier session, if any.
    /// - Throws: `GameBoyError` if the data isn't a ROM this emulator can run.
    func loadCartridge(data: Data, save: Data? = nil) throws {
        // The cartridge header, which says what hardware the cartridge has, ends at 0x014F
        guard data.count >= 0x150 else {
            throw GameBoyError.invalidROM
        }
        // No bank controller, MBC1, MBC3 or MBC5. Anything else would run with the wrong
        // banking and crash in confusing ways, so it is refused up front.
        let type = data[data.startIndex + 0x147]
        guard [0x00, 0x08, 0x09].contains(type) || (0x01...0x03).contains(type)
                || (0x0F...0x13).contains(type) || (0x19...0x1E).contains(type) else {
            throw GameBoyError.unsupportedCartridge(type: type)
        }

        cartridgeData = [UInt8](data)

        // Bit 7 of this header byte marks a game made for the Game Boy Color
        isColorMode = cartridgeData[0x143] & 0x80 != 0
        vramBank = 0
        wramBank = 1
        bank1High = 0
        transferBlocksRemaining = 0
        isHBlankTransferActive = false

        // A Color game sets its own palettes. An original game gets the ones the Game Boy
        // Color's boot program would pick for it: background palette 0 and sprite palettes
        // 0 and 1, which the PPU then uses in place of four shades of grey.
        backgroundPalettes = [UInt8](repeating: 0xFF, count: 64)
        objectPalettes = [UInt8](repeating: 0xFF, count: 64)
        if !isColorMode {
            let palettes = CompatibilityPalettes.palettes(forROM: cartridgeData)
            for (index, color) in palettes.background.enumerated() {
                backgroundPalettes[index * 2] = UInt8(color & 0xFF)
                backgroundPalettes[index * 2 + 1] = UInt8(color >> 8)
            }
            for (index, color) in (palettes.object0 + palettes.object1).enumerated() {
                objectPalettes[index * 2] = UInt8(color & 0xFF)
                objectPalettes[index * 2 + 1] = UInt8(color >> 8)
            }
        }

        // The header gives the size of the cartridge RAM; only the largest kind needs
        // more than the default 4 banks
        let ramBankCount = cartridgeData[0x149] == 0x04 ? 16 : cartridgeData[0x149] == 0x05 ? 8 : 4
        externalRam = Array(repeating: 0, count: ramBankCount * RAM_BANK_SIZE)
        if let save {
            externalRam.replaceSubrange(0..<min(save.count, externalRam.count), with: save.prefix(externalRam.count))
        }
        hasUnsavedExternalRam = false
        bank1 = 1
        bank2 = 0
        mode = .rom
    }

    /// Advances the timer and raises the timer interrupt when it overflows.
    func tickClock(cycles: Int) {
        if clock.tick(cycles: cycles) {
            self[INTERRUPT_FLAG_REGISTER] |= 0x04
        }
    }

    private func initializeHardware() {
        // LCD Registers (DMA is left alone, writing it would start a transfer)
        self[0xFF40] = 0x91 // LCDC: LCD Control
        self[0xFF41] = 0x00 // STAT: LCDC Status
        self[0xFF42] = 0x00 // SCY: Scroll Y
        self[0xFF43] = 0x00 // SCX: Scroll X
        self[0xFF44] = 0x00 // LY: LCDC Y-Coordinate
        self[0xFF45] = 0x00 // LYC: LY Compare
        self[0xFF47] = 0xFC // BGP: BG Palette Data
        self[0xFF48] = 0xFF // OBP0: Object Palette 0 Data
        self[0xFF49] = 0xFF // OBP1: Object Palette 1 Data
        self[0xFF4A] = 0x00 // WY: Window Y Position
        self[0xFF4B] = 0x00 // WX: Window X Position

        // Disable all interrupts
        self[0xFFFF] = 0x00 // IE: Interrupt Enable
        self[0xFF0F] = 0xE1 // IF: Interrupt Flag
    }

    // MARK: - Joypad

    /// The 8 buttons share 4 input lines. The game first writes which half it wants to read
    /// (bit 4 low = d-pad, bit 5 low = action buttons), then reads the lower 4 bits.
    /// A pressed button reads as 0, a released one as 1.
    private func readJoypad() -> UInt8 {
        let select = ioPorts[0] & 0x30
        var pressed: UInt8 = 0

        if select & 0x10 == 0 {
            switch joypad.dPadState {
            case .right: pressed |= 0x01
            case .left:  pressed |= 0x02
            case .up:    pressed |= 0x04
            case .down:  pressed |= 0x08
            case .idle:  break
            }
        }
        if select & 0x20 == 0 {
            if joypad.aButtonPressed { pressed |= 0x01 }
            if joypad.bButtonPressed { pressed |= 0x02 }
            if joypad.selectButtonPressed { pressed |= 0x04 }
            if joypad.startButtonPressed { pressed |= 0x08 }
        }

        return 0xC0 | select | (~pressed & 0x0F)
    }

    // MARK: - Bank Switching

    /// Handles a write to one of the color palette data registers. The index register picks
    /// which of the 64 bytes is written, and can be set to move on to the next one by itself.
    private func writePaletteData(_ value: UInt8, to palettes: inout [UInt8], indexRegister: Int) {
        let index = ioPorts[indexRegister - IO_PORTS_START]
        palettes[Int(index & 0x3F)] = value
        if index & 0x80 != 0 {
            ioPorts[indexRegister - IO_PORTS_START] = 0x80 | ((index &+ 1) & 0x3F)
        }
    }

    /// Handles a write to the HDMA control register, which starts or stops a transfer.
    ///
    /// Bit 7 picks the kind of transfer and the other bits give its length, in blocks of
    /// 16 bytes, minus one. With bit 7 clear everything is copied at once. With bit 7 set,
    /// one block is copied in each HBlank from then on, which lets a game update graphics
    /// while the screen is being drawn.
    ///
    /// Writing with bit 7 clear while an HBlank transfer is running doesn't start anything:
    /// it stops that transfer. Games use this to copy an exact number of blocks.
    private func writeTransferControl(_ value: UInt8) {
        if isHBlankTransferActive && value & 0x80 == 0 {
            isHBlankTransferActive = false
            return
        }

        transferBlocksRemaining = Int(value & 0x7F) + 1

        if value & 0x80 == 0 {
            while transferBlocksRemaining > 0 {
                transferBlock()
            }
        } else {
            isHBlankTransferActive = true
            // With the LCD off there are no HBlanks; the hardware copies one block right away
            if self[0xFF40] & 0x80 == 0 {
                transferBlock()
            }
        }
    }

    /// Copies the next 16 bytes of the current transfer into video RAM.
    private func transferBlock() {
        for offset in 0..<16 {
            let destination = VRAM_START + ((transferDestination + offset) & 0x1FFF)
            self[destination] = self[(transferSource + offset) & 0xFFFF]
        }
        // The addresses move along, so a following transfer carries on where this one ended
        transferSource += 16
        transferDestination += 16
        transferBlocksRemaining -= 1
        if transferBlocksRemaining == 0 {
            isHBlankTransferActive = false
        }
    }

    func horizontalBlankDidStart() {
        if isHBlankTransferActive {
            transferBlock()
        }
    }

    private func writeBank1(address: Int, value: UInt8) {
        guard cartridgeType != 0 else {
            return // A plain 32KB cartridge has no bank controller
        }
        if isMBC5 {
            // MBC5 has a 9-bit bank number split over two registers, and bank 0 is allowed
            if address < 0x3000 {
                bank1 = value
            } else {
                bank1High = value & 0x01
            }
            return
        }
        bank1 = value & (isMBC3 ? 0x7F : 0x1F)
        if bank1 == 0 {
            bank1 = 1
        }
    }

    // MARK: - PPU access

    func videoRAM(bank: Int, address: Int) -> UInt8 {
        vram[bank * VRAM_BANK_SIZE + address - VRAM_START]
    }

    func colorPaletteEntry(isObject: Bool, index: Int) -> UInt16 {
        let palettes = isObject ? objectPalettes : backgroundPalettes
        return UInt16(palettes[index * 2]) | UInt16(palettes[index * 2 + 1]) << 8
    }
}

protocol AddressBusProtocol {
    subscript(address: Int) -> UInt8 { get set }

    /// Whether the machine runs as a Game Boy Color.
    var isColorMode: Bool { get }

    /// Reads video RAM (0x8000-0x9FFF) from a specific bank. The PPU sees both banks at
    /// all times, whichever one the game currently has selected for itself.
    func videoRAM(bank: Int, address: Int) -> UInt8

    /// One of the 32 background or 32 sprite colors, as 15-bit RGB with red in the low bits.
    func colorPaletteEntry(isObject: Bool, index: Int) -> UInt16

    /// Called by the PPU each time it finishes drawing a visible scanline.
    func horizontalBlankDidStart()
}
