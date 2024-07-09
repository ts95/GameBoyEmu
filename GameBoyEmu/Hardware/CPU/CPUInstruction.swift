//
//  CPUInstruction.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 08/07/2024.
//

import Foundation

enum CPURegister: UInt8 {
    case B = 0b000
    case C = 0b001
    case D = 0b010
    case E = 0b011
    case H = 0b100
    case L = 0b101
    case F = 0b110 // Flags register
    case A = 0b111 // Accumulator register
}

enum JumpCondition: UInt8 {
    case NZ = 0b00 // Not Zero
    case Z = 0b01  // Zero
    case NC = 0b10 // Not Carry
    case C = 0b11  // Carry
}

/// An enumeration that represents the number of T cycles (clock cycles) an instruction takes to execute in the Game Boy CPU.
///
/// T cycles are the fundamental time unit in the Game Boy CPU, representing the smallest unit of work the CPU performs.
/// Each T cycle corresponds to one clock pulse of the 4.19 MHz oscillator.
///
/// This enumeration helps to distinguish between instructions with a constant number of T cycles and those with a variable number of T cycles depending on conditions.
enum TCycles {
    case constant(Int)
    case variable(min: Int, max: Int)

    func count(conditionMet: Bool = false) -> Int {
        switch self {
        case .constant(let value):
            return value
        case .variable(let min, let max):
            return conditionMet ? max : min
        }
    }
}

enum CPUInstruction {

    // MARK: 8-bit Load Instructions

    /// LD r, r'
    case loadRegister(CPURegister, CPURegister)
    /// LD r, n
    case loadRegisterFromImmediate(CPURegister)
    /// LD r, (HL)
    case loadRegisterFromAddressHL(CPURegister)
    /// LD (HL), r
    case loadAddressHLFromRegister(CPURegister)
    /// LD (HL), n
    case loadAddressHLFromImmediate
    /// LD A, (BC)
    case loadAFromAddressBC
    /// LD A, (DE)
    case loadAFromAddressDE
    /// LD (BC), A
    case loadAddressBCFromA
    /// LD (DE), A
    case loadAddressDEFromA
    /// LD A, (nn)
    case loadAFromAddressNN
    /// LD (nn), A
    case loadAddressNNFromA
    /// LD A, (C)
    case loadAFromAddressFF00PlusC
    /// LD (C), A
    case loadAddressFF00PlusCFromA
    /// LD A, (n)
    case loadAFromAddressFF00PlusN
    /// LD (n), A
    case loadAddressFF00PlusNFromA
    /// LDD A, (HL)
    case loadAFromAddressHLAndDecrement
    /// LDD (HL), A
    case loadAddressHLAndDecrementFromA
    /// LDI A, (HL)
    case loadAFromAddressHLAndIncrement
    /// LDI (HL), A
    case loadAddressHLAndIncrementFromA

    // MARK: 16-bit Load Instructions

    /// LD dd, nn
    case loadRegisterPairFromImmediate(CPURegister, CPURegister)
    /// LD (nn), SP
    case loadAddressNNFromSP
    /// LD SP, HL
    case loadSPFromHL
    /// PUSH qq
    case pushRegisterPair(CPURegister, CPURegister)
    /// POP qq
    case popRegisterPair(CPURegister, CPURegister)
    /// LDHL SP, e
    case loadHLFromSPPlusE

    // MARK: 8-bit Arithmetic and Logical Instructions

    /// ADD A, r
    case addAWithRegister(CPURegister)
    /// ADD A, (HL)
    case addAWithAddressHL
    /// ADD A, n
    case addAWithImmediate
    /// ADC A, r
    case addAWithCarryRegister(CPURegister)
    /// ADC A, (HL)
    case addAWithCarryAddressHL
    /// ADC A, n
    case addAWithCarryImmediate
    /// SUB r
    case subtractAWithRegister(CPURegister)
    /// SUB (HL)
    case subtractAWithAddressHL
    /// SUB n
    case subtractAWithImmediate
    /// SBC A, r
    case subtractAWithCarryRegister(CPURegister)
    /// SBC A, (HL)
    case subtractAWithCarryAddressHL
    /// SBC A, n
    case subtractAWithCarryImmediate
    /// CP r
    case compareAWithRegister(CPURegister)
    /// CP (HL)
    case compareAWithAddressHL
    /// CP n
    case compareAWithImmediate
    /// INC r
    case incrementRegister(CPURegister)
    /// INC (HL)
    case incrementAddressHL
    /// DEC r
    case decrementRegister(CPURegister)
    /// DEC (HL)
    case decrementAddressHL
    /// AND r
    case bitwiseAndWithRegister(CPURegister)
    /// AND (HL)
    case bitwiseAndWithAddressHL
    /// AND n
    case bitwiseAndWithImmediate
    /// OR r
    case bitwiseOrWithRegister(CPURegister)
    /// OR (HL)
    case bitwiseOrWithAddressHL
    /// OR n
    case bitwiseOrWithImmediate
    /// XOR r
    case bitwiseXorWithRegister(CPURegister)
    /// XOR (HL)
    case bitwiseXorWithAddressHL
    /// XOR n
    case bitwiseXorWithImmediate
    /// CCF
    case complementCarryFlag
    /// SCF
    case setCarryFlag
    /// DAA
    case decimalAdjustAccumulator
    /// CPL
    case complementAccumulator

    // MARK: 16-bit Arithmetic Instructions

    /// INC ss
    case incrementRegisterPair(CPURegister, CPURegister)
    /// DEC ss
    case decrementRegisterPair(CPURegister, CPURegister)
    /// ADD HL, ss
    case addHLWithRegisterPair(CPURegister, CPURegister)
    /// ADD SP, e
    case addSPWithE

    // MARK: Rotate, Shift, and Bit Operation Instructions

    /// RLCA
    case rotateLeftCircularAccumulator
    /// RRCA
    case rotateRightCircularAccumulator
    /// RLA
    case rotateLeftAccumulator
    /// RRA
    case rotateRightAccumulator
    /// RLC r
    case rotateLeftCircularRegister(CPURegister)
    /// RLC (HL)
    case rotateLeftCircularAddressHL
    /// RRC r
    case rotateRightCircularRegister(CPURegister)
    /// RRC (HL)
    case rotateRightCircularAddressHL
    /// RL r
    case rotateLeftRegister(CPURegister)
    /// RL (HL)
    case rotateLeftAddressHL
    /// RR r
    case rotateRightRegister(CPURegister)
    /// RR (HL)
    case rotateRightAddressHL
    /// SLA r
    case shiftLeftArithmeticRegister(CPURegister)
    /// SLA (HL)
    case shiftLeftArithmeticAddressHL
    /// SRA r
    case shiftRightArithmeticRegister(CPURegister)
    /// SRA (HL)
    case shiftRightArithmeticAddressHL
    /// SWAP r
    case swapNibblesRegister(CPURegister)
    /// SWAP (HL)
    case swapNibblesAddressHL
    /// SRL r
    case shiftRightLogicalRegister(CPURegister)
    /// SRL (HL)
    case shiftRightLogicalAddressHL
    /// BIT b, r
    case testBitRegister(UInt8, CPURegister)
    /// BIT b, (HL)
    case testBitAddressHL(UInt8)
    /// RES b, r
    case resetBitRegister(UInt8, CPURegister)
    /// RES b, (HL)
    case resetBitAddressHL(UInt8)
    /// SET b, r
    case setBitRegister(UInt8, CPURegister)
    /// SET b, (HL)
    case setBitAddressHL(UInt8)

    // MARK: Control Flow Instructions

    /// JP nn
    case jump(UInt16)
    /// JP (HL)
    case jumpToHL
    /// JP cc, nn
    case jumpConditional(JumpCondition, UInt16)
    /// JR e
    case relativeJump(Int8)
    /// JR cc, e
    case relativeJumpConditional(JumpCondition, Int8)
    /// CALL nn
    case callFunction(UInt16)
    /// CALL cc, nn
    case callFunctionConditional(JumpCondition, UInt16)
    /// RET
    case returnFromFunction
    /// RET cc
    case returnFromFunctionConditional(JumpCondition)
    /// RETI
    case returnFromInterruptHandler
    /// RST n
    case restartCallFunction(UInt8)

    // MARK: Miscellaneous Instructions

    /// HALT
    case haltSystemClock
    /// STOP
    case stopSystemAndMainClocks
    /// DI
    case disableInterrupts
    /// EI
    case enableInterrupts
    /// NOP
    case noOperation
    
    var cycles: TCycles {
        switch self {
        case .noOperation:
            return .constant(4)
        case .loadRegister:
            return .constant(4)
        case .loadRegisterFromImmediate:
            return .constant(8)
        case .loadAFromAddressBC, .loadAFromAddressDE, .loadAddressBCFromA, .loadAddressDEFromA:
            return .constant(8)
        case .loadAFromAddressNN, .loadAddressNNFromA:
            return .constant(16)
        case .addAWithRegister, .subtractAWithRegister, .compareAWithRegister:
            return .constant(4)
        case .addAWithImmediate, .subtractAWithImmediate, .compareAWithImmediate:
            return .constant(8)
        case .addAWithAddressHL, .subtractAWithAddressHL, .compareAWithAddressHL:
            return .constant(8)
        case .jump:
            return .constant(16)
        case .jumpConditional:
            return .variable(min: 12, max: 16)
        case .relativeJump:
            return .constant(12)
        case .relativeJumpConditional:
            return .variable(min: 8, max: 12)
        case .callFunction:
            return .constant(24)
        case .callFunctionConditional:
            return .variable(min: 12, max: 24)
        case .returnFromFunction:
            return .constant(16)
        case .returnFromFunctionConditional:
            return .variable(min: 8, max: 20)
        case .returnFromInterruptHandler:
            return .constant(16)
        case .pushRegisterPair:
            return .constant(16)
        case .popRegisterPair:
            return .constant(12)
        case .rotateLeftCircularAccumulator, .rotateLeftAccumulator, .rotateRightCircularAccumulator, .rotateRightAccumulator:
            return .constant(4)
        case .haltSystemClock, .stopSystemAndMainClocks:
            return .constant(4)
        default:
            return .constant(4) // Default cycle count for unspecified instructions
        }
    }

//    var opcode: UInt8 {
//        switch self {
//            // 8-bit Load Instructions
//        case .loadRegister(let dest, let src):
//            return 0b01000000 | (dest.rawValue << 3) | src.rawValue
//        case .loadRegisterFromImmediate(let dest):
//            switch dest {
//            case .B: return 0x06
//            case .C: return 0x0E
//            case .D: return 0x16
//            case .E: return 0x1E
//            case .H: return 0x26
//            case .L: return 0x2E
//            case .A: return 0x3E
//            default: fatalError("Invalid register for load immediate: \(dest)")
//            }
//        case .loadRegisterFromAddressHL(let dest):
//            return 0b01000110 | (dest.rawValue << 3)
//        case .loadAddressHLFromRegister(let src):
//            return 0b01110000 | src.rawValue
//        case .loadAddressHLFromImmediate:
//            return 0x36
//        case .loadAFromAddressBC:
//            return 0x0A
//        case .loadAFromAddressDE:
//            return 0x1A
//        case .loadAddressBCFromA:
//            return 0x02
//        case .loadAddressDEFromA:
//            return 0x12
//        case .loadAFromAddressNN:
//            return 0xFA
//        case .loadAddressNNFromA:
//            return 0xEA
//        case .loadAFromAddressFF00PlusC:
//            return 0xF2
//        case .loadAddressFF00PlusCFromA:
//            return 0xE2
//        case .loadAFromAddressFF00PlusN:
//            return 0xF0
//        case .loadAddressFF00PlusNFromA:
//            return 0xE0
//        case .loadAFromAddressHLAndDecrement:
//            return 0x3A
//        case .loadAddressHLAndDecrementFromA:
//            return 0x32
//        case .loadAFromAddressHLAndIncrement:
//            return 0x2A
//        case .loadAddressHLAndIncrementFromA:
//            return 0x22
//
//            // 16-bit Load Instructions
//        case .loadRegisterPairFromImmediate(let high, let low):
//            switch (high, low) {
//            case (.B, .C): return 0x01
//            case (.D, .E): return 0x11
//            case (.H, .L): return 0x21
//            case (.A, .F): return 0x31
//            default: fatalError("Invalid register pair for instruction")
//            }
//        case .loadAddressNNFromSP:
//            return 0x08
//        case .loadSPFromHL:
//            return 0xF9
//        case .pushRegisterPair(let high, let low):
//            switch (high, low) {
//            case (.B, .C): return 0xC5
//            case (.D, .E): return 0xD5
//            case (.H, .L): return 0xE5
//            case (.A, .F): return 0xF5
//            default: fatalError("Invalid register pair for instruction")
//            }
//        case .popRegisterPair(let high, let low):
//            switch (high, low) {
//            case (.B, .C): return 0xC1
//            case (.D, .E): return 0xD1
//            case (.H, .L): return 0xE1
//            case (.A, .F): return 0xF1
//            default: fatalError("Invalid register pair for instruction")
//            }
//        case .loadHLFromSPPlusE:
//            return 0xF8
//
//            // 8-bit Arithmetic and Logical Instructions
//        case .addAWithRegister(let src):
//            return 0b10000000 | src.rawValue
//        case .addAWithAddressHL:
//            return 0x86
//        case .addAWithImmediate:
//            return 0xC6
//        case .addAWithCarryRegister(let src):
//            return 0b10001000 | src.rawValue
//        case .addAWithCarryAddressHL:
//            return 0x8E
//        case .addAWithCarryImmediate:
//            return 0xCE
//        case .subtractAWithRegister(let src):
//            return 0b10010000 | src.rawValue
//        case .subtractAWithAddressHL:
//            return 0x96
//        case .subtractAWithImmediate:
//            return 0xD6
//        case .subtractAWithCarryRegister(let src):
//            return 0b10011000 | src.rawValue
//        case .subtractAWithCarryAddressHL:
//            return 0x9E
//        case .subtractAWithCarryImmediate:
//            return 0xDE
//        case .compareAWithRegister(let src):
//            return 0b10111000 | src.rawValue
//        case .compareAWithAddressHL:
//            return 0xBE
//        case .compareAWithImmediate:
//            return 0xFE
//        case .incrementRegister(let dest):
//            switch dest {
//            case .B: return 0x04
//            case .C: return 0x0C
//            case .D: return 0x14
//            case .E: return 0x1C
//            case .H: return 0x24
//            case .L: return 0x2C
//            case .A: return 0x3C
//            default: fatalError("Invalid register for load immediate: \(dest)")
//            }
//        case .incrementAddressHL:
//            return 0x34
//        case .decrementRegister(let dest):
//            switch dest {
//            case .B: return 0x05
//            case .C: return 0x0D
//            case .D: return 0x15
//            case .E: return 0x1D
//            case .H: return 0x25
//            case .L: return 0x2D
//            case .A: return 0x3D
//            default: fatalError("Invalid register for load immediate: \(dest)")
//            }
//        case .decrementAddressHL:
//            return 0x35
//        case .bitwiseAndWithRegister(let src):
//            return 0b10100000 | src.rawValue
//        case .bitwiseAndWithAddressHL:
//            return 0xA6
//        case .bitwiseAndWithImmediate:
//            return 0xE6
//        case .bitwiseOrWithRegister(let src):
//            return 0b10110000 | src.rawValue
//        case .bitwiseOrWithAddressHL:
//            return 0xB6
//        case .bitwiseOrWithImmediate:
//            return 0xF6
//        case .bitwiseXorWithRegister(let src):
//            return 0b10101000 | src.rawValue
//        case .bitwiseXorWithAddressHL:
//            return 0xAE
//        case .bitwiseXorWithImmediate:
//            return 0xEE
//        case .complementCarryFlag:
//            return 0x3F
//        case .setCarryFlag:
//            return 0x37
//        case .decimalAdjustAccumulator:
//            return 0x27
//        case .complementAccumulator:
//            return 0x2F
//
//            // 16-bit Arithmetic Instructions
//        case .incrementRegisterPair(let high, let low):
//            switch (high, low) {
//            case (.B, .C): return 0x03
//            case (.D, .E): return 0x13
//            case (.H, .L): return 0x23
//            case (.A, .F): return 0x33
//            default: fatalError("Invalid register pair for instruction")
//            }
//        case .decrementRegisterPair(let high, let low):
//            switch (high, low) {
//            case (.B, .C): return 0x0B
//            case (.D, .E): return 0x1B
//            case (.H, .L): return 0x2B
//            case (.A, .F): return 0x3B
//            default: fatalError("Invalid register pair for instruction")
//            }
//        case .addHLWithRegisterPair(let high, let low):
//            switch (high, low) {
//            case (.B, .C): return 0x09
//            case (.D, .E): return 0x19
//            case (.H, .L): return 0x29
//            case (.A, .F): return 0x39
//            default: fatalError("Invalid register pair for instruction")
//            }
//        case .addSPWithE:
//            return 0xE8
//
//            // Rotate, Shift, and Bit Operation Instructions
//        case .rotateLeftCircularAccumulator:
//            return 0x07
//        case .rotateRightCircularAccumulator:
//            return 0x0F
//        case .rotateLeftAccumulator:
//            return 0x17
//        case .rotateRightAccumulator:
//            return 0x1F
//        case .rotateLeftCircularRegister(let dest):
//            return 0xCB << 8 | 0x00 | dest.rawValue
//        case .rotateLeftCircularAddressHL:
//            return 0xCB << 8 | 0x06
//        case .rotateRightCircularRegister(let dest):
//            return 0xCB << 8 | 0x08 | dest.rawValue
//        case .rotateRightCircularAddressHL:
//            return 0xCB << 8 | 0x0E
//        case .rotateLeftRegister(let dest):
//            return 0xCB << 8 | 0x10 | dest.rawValue
//        case .rotateLeftAddressHL:
//            return 0xCB << 8 | 0x16
//        case .rotateRightRegister(let dest):
//            return 0xCB << 8 | 0x18 | dest.rawValue
//        case .rotateRightAddressHL:
//            return 0xCB << 8 | 0x1E
//        case .shiftLeftArithmeticRegister(let dest):
//            return 0xCB << 8 | 0x20 | dest.rawValue
//        case .shiftLeftArithmeticAddressHL:
//            return 0xCB << 8 | 0x26
//        case .shiftRightArithmeticRegister(let dest):
//            return 0xCB << 8 | 0x28 | dest.rawValue
//        case .shiftRightArithmeticAddressHL:
//            return 0xCB << 8 | 0x2E
//        case .swapNibblesRegister(let dest):
//            return 0xCB << 8 | 0x30 | dest.rawValue
//        case .swapNibblesAddressHL:
//            return 0xCB << 8 | 0x36
//        case .shiftRightLogicalRegister(let dest):
//            return 0xCB << 8 | 0x38 | dest.rawValue
//        case .shiftRightLogicalAddressHL:
//            return 0xCB << 8 | 0x3E
//        case .testBitRegister(let bit, let dest):
//            guard bit < 8 else { fatalError("Bit out of range") }
//            return 0xCB << 8 | 0x40 | (bit << 3) | dest.rawValue
//        case .testBitAddressHL(let bit):
//            guard bit < 8 else { fatalError("Bit out of range") }
//            return 0xCB << 8 | 0x46 | (bit << 3)
//        case .resetBitRegister(let bit, let dest):
//            guard bit < 8 else { fatalError("Bit out of range") }
//            return 0xCB << 8 | 0x80 | (bit << 3) | dest.rawValue
//        case .resetBitAddressHL(let bit):
//            guard bit < 8 else { fatalError("Bit out of range") }
//            return 0xCB << 8 | 0x86 | (bit << 3)
//        case .setBitRegister(let bit, let dest):
//            guard bit < 8 else { fatalError("Bit out of range") }
//            return 0xCB << 8 | 0xC0 | (bit << 3) | dest.rawValue
//        case .setBitAddressHL(let bit):
//            guard bit < 8 else { fatalError("Bit out of range") }
//            return 0xCB << 8 | 0xC6 | (bit << 3)
//
//            // Control Flow Instructions
//        case .jump:
//            return 0xC3
//        case .jumpToHL:
//            return 0xE9
//        case .jumpConditional(let condition, _):
//            return 0xC2 | (condition.rawValue << 3)
//        case .relativeJump:
//            return 0x18
//        case .relativeJumpConditional(let condition, _):
//            return 0x20 | (condition.rawValue << 3)
//        case .callFunction:
//            return 0xCD
//        case .callFunctionConditional(let condition, _):
//            return 0xC4 | (condition.rawValue << 3)
//        case .returnFromFunction:
//            return 0xC9
//        case .returnFromFunctionConditional(let condition):
//            return 0xC0 | (condition.rawValue << 3)
//        case .returnFromInterruptHandler:
//            return 0xD9
//        case .restartCallFunction(let address):
//            assert(address % 8 == 0 && address <= 0x38, "Invalid restart address")
//            return 0xC7 | address
//
//            // Miscellaneous Instructions
//        case .haltSystemClock:
//            return 0x76
//        case .stopSystemAndMainClocks:
//            return 0x10
//        case .disableInterrupts:
//            return 0xF3
//        case .enableInterrupts:
//            return 0xFB
//        case .noOperation:
//            return 0x00
//        }
//    }
}
