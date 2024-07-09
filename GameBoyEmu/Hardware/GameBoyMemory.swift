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

private let MBC1_ROM_BANK_NUMBER_START: Int = 0x2000
private let MBC1_ROM_BANK_NUMBER_END: Int = 0x3FFF
private let MBC1_RAM_BANK_NUMBER_START: Int = 0x4000
private let MBC1_RAM_BANK_NUMBER_END: Int = 0x5FFF
private let MBC1_BANKING_MODE_START: Int = 0x6000
private let MBC1_BANKING_MODE_END: Int = 0x7FFF

enum BankingMode: UInt8 {
    case rom = 0
    case ram = 1
}

class GameBoyMemory: MemoryAddressInterface {

    // MARK: - CPU memory

    // ROM Bank 0: Contains the first 16KB of the game ROM.
    var romBank0: Array<UInt8>

    // ROM Bank 1: Contains the second 16KB of the game ROM, supports bank switching.
    var romBank1: Array<UInt8>

    // External RAM: Optional RAM on the cartridge, often battery-backed for saving games.
    var externalRam: Array<UInt8>

    // Work RAM: General-purpose RAM used by the CPU for various tasks.
    var wram: Array<UInt8>

    // Echo RAM: A mirror of Work RAM, generally not used directly.
    var echoRam: ArraySlice<UInt8> {
        wram[(ECHO_RAM_START - WRAM_START)...(ECHO_RAM_END - WRAM_START)]
    }

    // I/O Ports: Used for input/output operations and hardware control registers.
    var ioPorts: Array<UInt8>

    // High RAM: Fast RAM used for stack and immediate data storage.
    var hram: Array<UInt8>

    // Single bit determining whether CPU interrupt is enabled.
    var interruptEnableReg = false

    // MARK: - PPU memory

    // Video RAM: Used by the PPU for tile data and attributes.
    var vram: Array<UInt8>

    // Object Attribute Memory: Used by the PPU for sprite attributes.
    var oam: Array<UInt8>

    // MARK: - Miscellaneous

    // All the ROM data of a Game Boy cartridge. Used for loading the inital ROM bank state,
    // and for switching the data in ROM bank 1.
    var cartridgeData = Data()

    // Bank registers
    var bank1: UInt8 = 1 // Bank 1 (5 bits)
    var bank2: UInt8 = 0 // Bank 2 (2 bits)
    var mode: BankingMode = .rom // Mode register

    // MARK: - Initializer

    init() {
        romBank0 = Array(repeating: 0, count: ROM_BANK_0_END - ROM_BANK_0_START + 1)
        romBank1 = Array(repeating: 0, count: ROM_BANK_1_END - ROM_BANK_1_START + 1)
        externalRam = Array(repeating: 0, count: EXTERNAL_RAM_END - EXTERNAL_RAM_START + 1)
        wram = Array(repeating: 0, count: WRAM_END - WRAM_START + 1)
        ioPorts = Array(repeating: 0, count: IO_PORTS_END - IO_PORTS_START + 1)
        hram = Array(repeating: 0, count: HRAM_END - HRAM_START + 1)
        vram = Array(repeating: 0, count: VRAM_END - VRAM_START + 1)
        oam = Array(repeating: 0, count: OAM_END - OAM_START + 1)
    }

    // Subscript to access memory using the 0x0000 to 0xFFFF address format
    subscript(address: Int) -> UInt8 {
        get {
            switch address {
            case ROM_BANK_0_START...ROM_BANK_0_END:
                return romBank0[address - ROM_BANK_0_START]
            case ROM_BANK_1_START...ROM_BANK_1_END:
                return romBank1[address - ROM_BANK_1_START]
            case VRAM_START...VRAM_END:
                return vram[address - VRAM_START]
            case EXTERNAL_RAM_START...EXTERNAL_RAM_END:
                return externalRam[address - EXTERNAL_RAM_START]
            case WRAM_START...WRAM_END:
                return wram[address - WRAM_START]
            case ECHO_RAM_START...ECHO_RAM_END:
                return wram[address - (ECHO_RAM_START - WRAM_START)]
            case OAM_START...OAM_END:
                return oam[address - OAM_START]
            case IO_PORTS_START...IO_PORTS_END:
                return ioPorts[address - IO_PORTS_START]
            case HRAM_START...HRAM_END:
                return hram[address - HRAM_START]
            case INTERRUPT_ENABLE_REGISTER:
                return interruptEnableReg ? 1 : 0
            default:
                // Out of bounds access returns 0
                return 0
            }
        }
        set {
            switch address {
            case ROM_BANK_0_START...ROM_BANK_0_END:
                romBank0[address - ROM_BANK_0_START] = newValue
            case ROM_BANK_1_START...ROM_BANK_1_END:
                romBank1[address - ROM_BANK_1_START] = newValue
            case VRAM_START...VRAM_END:
                vram[address - VRAM_START] = newValue
            case EXTERNAL_RAM_START...EXTERNAL_RAM_END:
                externalRam[address - EXTERNAL_RAM_START] = newValue
            case WRAM_START...WRAM_END:
                wram[address - WRAM_START] = newValue
            case ECHO_RAM_START...ECHO_RAM_END:
                wram[address - (ECHO_RAM_START - WRAM_START)] = newValue
            case OAM_START...OAM_END:
                oam[address - OAM_START] = newValue
            case IO_PORTS_START...IO_PORTS_END:
                ioPorts[address - IO_PORTS_START] = newValue
            case HRAM_START...HRAM_END:
                hram[address - HRAM_START] = newValue
            case INTERRUPT_ENABLE_REGISTER:
                interruptEnableReg = newValue != 0
            case MBC1_ROM_BANK_NUMBER_START...MBC1_ROM_BANK_NUMBER_END:
                writeBank1(value: newValue)
            case MBC1_RAM_BANK_NUMBER_START...MBC1_RAM_BANK_NUMBER_END:
                writeBank2(value: newValue)
            case MBC1_BANKING_MODE_START...MBC1_BANKING_MODE_END:
                writeMode(value: newValue)
            default:
                // Ignore writes to out of bounds addresses
                break
            }
        }
    }

    func loadCartridge(data: Data) {
        cartridgeData = data

        // Copy initial cartridge data into ROM banks
        for (index, byte) in data.prefix(ROM_BANK_1_END).enumerated() {
            self[index] = byte
        }
    }
    
    // MARK: - Bank Switching

    private func writeBank1(value: UInt8) {
        bank1 = value & 0x1F
        if bank1 == 0 {
            bank1 = 1
        }
        updateROMBank1()
    }

    private func writeBank2(value: UInt8) {
        bank2 = value & 0x03
        updateROMBank1()
    }

    private func writeMode(value: UInt8) {
        if let newMode = BankingMode(rawValue: value & 0x01) {
            mode = newMode
        }
    }

    private func updateROMBank1() {
        let bankNumber = Int(bank1) | (Int(bank2) << 5)
        let start = bankNumber * (ROM_BANK_1_END - ROM_BANK_1_START + 1)
        let end = start + (ROM_BANK_1_END - ROM_BANK_1_START)
        romBank1 = Array(cartridgeData[start...end])
    }
}

protocol MemoryAddressInterface {
    subscript(address: Int) -> UInt8 { get set }
}
