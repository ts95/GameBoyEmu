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
    /// Flags register. Note that in an opcode's 3-bit register field, 0b110 does NOT mean F,
    /// it means "the byte at address HL". The decoder must pick the `...AddressHL` instruction
    /// for those opcodes; F is only ever reached through PUSH AF / POP AF.
    case F = 0b110
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
    /// LD SP, nn
    case loadSPFromImmediate
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
    /// INC SP
    case incrementSP
    /// DEC SP
    case decrementSP
    /// ADD HL, SP
    case addHLWithSP
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
        // Rule of thumb: every byte the CPU reads or writes on the bus (opcode bytes included)
        // costs 4 T cycles, plus 4 extra for some 16-bit work. No `default` on purpose, so the
        // compiler forces a decision for every instruction.
        switch self {
        // 8-bit loads
        case .loadRegister:
            return .constant(4)
        case .loadRegisterFromImmediate, .loadRegisterFromAddressHL, .loadAddressHLFromRegister:
            return .constant(8)
        case .loadAddressHLFromImmediate:
            return .constant(12)
        case .loadAFromAddressBC, .loadAFromAddressDE, .loadAddressBCFromA, .loadAddressDEFromA:
            return .constant(8)
        case .loadAFromAddressNN, .loadAddressNNFromA:
            return .constant(16)
        case .loadAFromAddressFF00PlusC, .loadAddressFF00PlusCFromA:
            return .constant(8)
        case .loadAFromAddressFF00PlusN, .loadAddressFF00PlusNFromA:
            return .constant(12)
        case .loadAFromAddressHLAndDecrement, .loadAddressHLAndDecrementFromA,
             .loadAFromAddressHLAndIncrement, .loadAddressHLAndIncrementFromA:
            return .constant(8)

        // 16-bit loads
        case .loadRegisterPairFromImmediate, .loadSPFromImmediate:
            return .constant(12)
        case .loadAddressNNFromSP:
            return .constant(20)
        case .loadSPFromHL:
            return .constant(8)
        case .pushRegisterPair:
            return .constant(16)
        case .popRegisterPair, .loadHLFromSPPlusE:
            return .constant(12)

        // 8-bit arithmetic and logic
        case .addAWithRegister, .addAWithCarryRegister, .subtractAWithRegister, .subtractAWithCarryRegister,
             .compareAWithRegister, .bitwiseAndWithRegister, .bitwiseOrWithRegister, .bitwiseXorWithRegister,
             .incrementRegister, .decrementRegister:
            return .constant(4)
        case .addAWithAddressHL, .addAWithCarryAddressHL, .subtractAWithAddressHL, .subtractAWithCarryAddressHL,
             .compareAWithAddressHL, .bitwiseAndWithAddressHL, .bitwiseOrWithAddressHL, .bitwiseXorWithAddressHL:
            return .constant(8)
        case .addAWithImmediate, .addAWithCarryImmediate, .subtractAWithImmediate, .subtractAWithCarryImmediate,
             .compareAWithImmediate, .bitwiseAndWithImmediate, .bitwiseOrWithImmediate, .bitwiseXorWithImmediate:
            return .constant(8)
        case .incrementAddressHL, .decrementAddressHL:
            return .constant(12)
        case .complementCarryFlag, .setCarryFlag, .decimalAdjustAccumulator, .complementAccumulator:
            return .constant(4)

        // 16-bit arithmetic
        case .incrementRegisterPair, .decrementRegisterPair, .incrementSP, .decrementSP,
             .addHLWithRegisterPair, .addHLWithSP:
            return .constant(8)
        case .addSPWithE:
            return .constant(16)

        // Rotates, shifts and bit operations (the CB-prefixed ones include the prefix byte)
        case .rotateLeftCircularAccumulator, .rotateLeftAccumulator, .rotateRightCircularAccumulator, .rotateRightAccumulator:
            return .constant(4)
        case .rotateLeftCircularRegister, .rotateRightCircularRegister, .rotateLeftRegister, .rotateRightRegister,
             .shiftLeftArithmeticRegister, .shiftRightArithmeticRegister, .swapNibblesRegister, .shiftRightLogicalRegister,
             .testBitRegister, .resetBitRegister, .setBitRegister:
            return .constant(8)
        case .rotateLeftCircularAddressHL, .rotateRightCircularAddressHL, .rotateLeftAddressHL, .rotateRightAddressHL,
             .shiftLeftArithmeticAddressHL, .shiftRightArithmeticAddressHL, .swapNibblesAddressHL, .shiftRightLogicalAddressHL,
             .resetBitAddressHL, .setBitAddressHL:
            return .constant(16)
        case .testBitAddressHL:
            return .constant(12)

        // Control flow
        case .jump:
            return .constant(16)
        case .jumpToHL:
            return .constant(4)
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
        case .returnFromFunction, .returnFromInterruptHandler, .restartCallFunction:
            return .constant(16)
        case .returnFromFunctionConditional:
            return .variable(min: 8, max: 20)

        // Miscellaneous
        case .haltSystemClock, .stopSystemAndMainClocks, .disableInterrupts, .enableInterrupts, .noOperation:
            return .constant(4)
        }
    }
}
