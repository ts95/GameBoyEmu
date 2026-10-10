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

private let BANK_SIZE = 0x4000
private let RAM_BANK_SIZE = 0x2000

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
    // Sized for the largest supported configuration, 4 banks of 8KB.
    var externalRam: Array<UInt8>

    // Work RAM: General-purpose RAM used by the CPU for various tasks.
    var wram: Array<UInt8>

    // I/O Ports: Used for input/output operations and hardware control registers.
    var ioPorts: Array<UInt8>

    // High RAM: Fast RAM used for stack and immediate data storage.
    var hram: Array<UInt8>

    // IE: one bit per interrupt source, selecting which interrupts the game wants to receive.
    var interruptEnableReg: UInt8 = 0

    // MARK: - PPU memory

    // Video RAM: Used by the PPU for tile data and attributes.
    var vram: Array<UInt8>

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
    var bank1: UInt8 = 1 // ROM bank number (5 bits on MBC1, 7 bits on MBC3)
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

    private var romBankOffset: Int {
        let bank = isMBC3 ? Int(bank1) : Int(bank1) | (Int(bank2) << 5)
        let bankCount = max(cartridgeData.count / BANK_SIZE, 2)
        return (bank % bankCount) * BANK_SIZE
    }

    private var ramBankOffset: Int {
        let bank = isMBC3 || mode == .ram ? Int(bank2 & 0x03) : 0
        return bank * RAM_BANK_SIZE
    }

    // MARK: - Initializer

    init() {
        externalRam = Array(repeating: 0, count: 4 * RAM_BANK_SIZE)
        wram = Array(repeating: 0, count: WRAM_END - WRAM_START + 1)
        ioPorts = Array(repeating: 0, count: IO_PORTS_END - IO_PORTS_START + 1)
        hram = Array(repeating: 0, count: HRAM_END - HRAM_START + 1)
        vram = Array(repeating: 0, count: VRAM_END - VRAM_START + 1)
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
                return vram[address - VRAM_START]
            case EXTERNAL_RAM_START...EXTERNAL_RAM_END:
                // ponytail: MBC3 real-time clock registers (bank2 >= 8) read as RAM bank 0-3.
                // Add an RTC if a game's in-game clock matters.
                return externalRam[ramBankOffset + address - EXTERNAL_RAM_START]
            case WRAM_START...WRAM_END:
                return wram[address - WRAM_START]
            case ECHO_RAM_START...ECHO_RAM_END:
                return wram[address - ECHO_RAM_START]
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
                writeBank1(value: newValue)
            case MBC_RAM_BANK_NUMBER_START...MBC_RAM_BANK_NUMBER_END:
                bank2 = isMBC3 ? newValue & 0x0F : newValue & 0x03
            case MBC_BANKING_MODE_START...MBC_BANKING_MODE_END:
                mode = BankingMode(rawValue: newValue & 0x01)!
            case ROM_BANK_0_START...ROM_BANK_1_END:
                // ponytail: 0x0000-0x1FFF is the external RAM enable switch. RAM is always
                // enabled here; honor it if a game depends on RAM being locked.
                break
            case VRAM_START...VRAM_END:
                vram[address - VRAM_START] = newValue
            case EXTERNAL_RAM_START...EXTERNAL_RAM_END:
                externalRam[ramBankOffset + address - EXTERNAL_RAM_START] = newValue
                hasUnsavedExternalRam = true
            case WRAM_START...WRAM_END:
                wram[address - WRAM_START] = newValue
            case ECHO_RAM_START...ECHO_RAM_END:
                wram[address - ECHO_RAM_START] = newValue
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
        // No bank controller, MBC1 or MBC3. Anything else would run with the wrong banking
        // and crash in confusing ways, so it is refused up front.
        let type = data[data.startIndex + 0x147]
        guard [0x00, 0x08, 0x09].contains(type) || (0x01...0x03).contains(type) || (0x0F...0x13).contains(type) else {
            throw GameBoyError.unsupportedCartridge(type: type)
        }

        cartridgeData = [UInt8](data)
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

    private func writeBank1(value: UInt8) {
        guard cartridgeType != 0 else {
            return // A plain 32KB cartridge has no bank controller
        }
        bank1 = value & (isMBC3 ? 0x7F : 0x1F)
        if bank1 == 0 {
            bank1 = 1
        }
    }
}

protocol AddressBusProtocol {
    subscript(address: Int) -> UInt8 { get set }
}
