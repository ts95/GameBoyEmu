//
//  CPUInstruction+CustomDebugStringConvertible.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 09/07/2024.
//

import Foundation

extension CPUInstruction: CustomDebugStringConvertible {

    var debugDescription: String {
        switch self {
        case .loadRegister(let reg1, let reg2):
            return "LD \(reg1), \(reg2)"
        case .loadRegisterFromImmediate(let reg):
            return "LD \(reg), n"
        case .loadRegisterFromAddressHL(let reg):
            return "LD \(reg), (HL)"
        case .loadAddressHLFromRegister(let reg):
            return "LD (HL), \(reg)"
        case .loadAddressHLFromImmediate:
            return "LD (HL), n"
        case .loadAFromAddressBC:
            return "LD A, (BC)"
        case .loadAFromAddressDE:
            return "LD A, (DE)"
        case .loadAddressBCFromA:
            return "LD (BC), A"
        case .loadAddressDEFromA:
            return "LD (DE), A"
        case .loadAFromAddressNN:
            return "LD A, (nn)"
        case .loadAddressNNFromA:
            return "LD (nn), A"
        case .loadAFromAddressFF00PlusC:
            return "LD A, (C)"
        case .loadAddressFF00PlusCFromA:
            return "LD (C), A"
        case .loadAFromAddressFF00PlusN:
            return "LD A, (n)"
        case .loadAddressFF00PlusNFromA:
            return "LD (n), A"
        case .loadAFromAddressHLAndDecrement:
            return "LDD A, (HL)"
        case .loadAddressHLAndDecrementFromA:
            return "LDD (HL), A"
        case .loadAFromAddressHLAndIncrement:
            return "LDI A, (HL)"
        case .loadAddressHLAndIncrementFromA:
            return "LDI (HL), A"

        case .loadRegisterPairFromImmediate(let reg1, let reg2):
            return "LD \(reg1)\(reg2), nn"
        case .loadAddressNNFromSP:
            return "LD (nn), SP"
        case .loadSPFromHL:
            return "LD SP, HL"
        case .pushRegisterPair(let reg1, let reg2):
            return "PUSH \(reg1)\(reg2)"
        case .popRegisterPair(let reg1, let reg2):
            return "POP \(reg1)\(reg2)"
        case .loadHLFromSPPlusE:
            return "LDHL SP, e"

        case .addAWithRegister(let reg):
            return "ADD A, \(reg)"
        case .addAWithAddressHL:
            return "ADD A, (HL)"
        case .addAWithImmediate:
            return "ADD A, n"
        case .addAWithCarryRegister(let reg):
            return "ADC A, \(reg)"
        case .addAWithCarryAddressHL:
            return "ADC A, (HL)"
        case .addAWithCarryImmediate:
            return "ADC A, n"
        case .subtractAWithRegister(let reg):
            return "SUB \(reg)"
        case .subtractAWithAddressHL:
            return "SUB (HL)"
        case .subtractAWithImmediate:
            return "SUB n"
        case .subtractAWithCarryRegister(let reg):
            return "SBC A, \(reg)"
        case .subtractAWithCarryAddressHL:
            return "SBC A, (HL)"
        case .subtractAWithCarryImmediate:
            return "SBC A, n"
        case .compareAWithRegister(let reg):
            return "CP \(reg)"
        case .compareAWithAddressHL:
            return "CP (HL)"
        case .compareAWithImmediate:
            return "CP n"
        case .incrementRegister(let reg):
            return "INC \(reg)"
        case .incrementAddressHL:
            return "INC (HL)"
        case .decrementRegister(let reg):
            return "DEC \(reg)"
        case .decrementAddressHL:
            return "DEC (HL)"
        case .bitwiseAndWithRegister(let reg):
            return "AND \(reg)"
        case .bitwiseAndWithAddressHL:
            return "AND (HL)"
        case .bitwiseAndWithImmediate:
            return "AND n"
        case .bitwiseOrWithRegister(let reg):
            return "OR \(reg)"
        case .bitwiseOrWithAddressHL:
            return "OR (HL)"
        case .bitwiseOrWithImmediate:
            return "OR n"
        case .bitwiseXorWithRegister(let reg):
            return "XOR \(reg)"
        case .bitwiseXorWithAddressHL:
            return "XOR (HL)"
        case .bitwiseXorWithImmediate:
            return "XOR n"
        case .complementCarryFlag:
            return "CCF"
        case .setCarryFlag:
            return "SCF"
        case .decimalAdjustAccumulator:
            return "DAA"
        case .complementAccumulator:
            return "CPL"

        case .incrementRegisterPair(let reg1, let reg2):
            return "INC \(reg1)\(reg2)"
        case .decrementRegisterPair(let reg1, let reg2):
            return "DEC \(reg1)\(reg2)"
        case .addHLWithRegisterPair(let reg1, let reg2):
            return "ADD HL, \(reg1)\(reg2)"
        case .addSPWithE:
            return "ADD SP, e"

        case .rotateLeftCircularAccumulator:
            return "RLCA"
        case .rotateRightCircularAccumulator:
            return "RRCA"
        case .rotateLeftAccumulator:
            return "RLA"
        case .rotateRightAccumulator:
            return "RRA"
        case .rotateLeftCircularRegister(let reg):
            return "RLC \(reg)"
        case .rotateLeftCircularAddressHL:
            return "RLC (HL)"
        case .rotateRightCircularRegister(let reg):
            return "RRC \(reg)"
        case .rotateRightCircularAddressHL:
            return "RRC (HL)"
        case .rotateLeftRegister(let reg):
            return "RL \(reg)"
        case .rotateLeftAddressHL:
            return "RL (HL)"
        case .rotateRightRegister(let reg):
            return "RR \(reg)"
        case .rotateRightAddressHL:
            return "RR (HL)"
        case .shiftLeftArithmeticRegister(let reg):
            return "SLA \(reg)"
        case .shiftLeftArithmeticAddressHL:
            return "SLA (HL)"
        case .shiftRightArithmeticRegister(let reg):
            return "SRA \(reg)"
        case .shiftRightArithmeticAddressHL:
            return "SRA (HL)"
        case .swapNibblesRegister(let reg):
            return "SWAP \(reg)"
        case .swapNibblesAddressHL:
            return "SWAP (HL)"
        case .shiftRightLogicalRegister(let reg):
            return "SRL \(reg)"
        case .shiftRightLogicalAddressHL:
            return "SRL (HL)"
        case .testBitRegister(let bit, let reg):
            return "BIT \(bit), \(reg)"
        case .testBitAddressHL(let bit):
            return "BIT \(bit), (HL)"
        case .resetBitRegister(let bit, let reg):
            return "RES \(bit), \(reg)"
        case .resetBitAddressHL(let bit):
            return "RES \(bit), (HL)"
        case .setBitRegister(let bit, let reg):
            return "SET \(bit), \(reg)"
        case .setBitAddressHL(let bit):
            return "SET \(bit), (HL)"

        case .jump(let addr):
            return String(format: "JP 0x%04X", addr)
        case .jumpToHL:
            return "JP (HL)"
        case .jumpConditional(let cond, let addr):
            return String(format: "JP \(cond), 0x%04X", addr)
        case .relativeJump(let offset):
            return String(format: "JR %d", offset)
        case .relativeJumpConditional(let cond, let offset):
            return String(format: "JR \(cond), %d", offset)
        case .callFunction(let addr):
            return String(format: "CALL 0x%04X", addr)
        case .callFunctionConditional(let cond, let addr):
            return String(format: "CALL \(cond), 0x%04X", addr)
        case .returnFromFunction:
            return "RET"
        case .returnFromFunctionConditional(let cond):
            return "RET \(cond)"
        case .returnFromInterruptHandler:
            return "RETI"
        case .restartCallFunction(let addr):
            return String(format: "RST 0x%02X", addr)

        case .haltSystemClock:
            return "HALT"
        case .stopSystemAndMainClocks:
            return "STOP"
        case .disableInterrupts:
            return "DI"
        case .enableInterrupts:
            return "EI"
        case .noOperation:
            return "NOP"
        }
    }
}

extension CPURegister: CustomDebugStringConvertible {

    var debugDescription: String {
        switch self {
        case .B: return "B"
        case .C: return "C"
        case .D: return "D"
        case .E: return "E"
        case .H: return "H"
        case .L: return "L"
        case .F: return "F"
        case .A: return "A"
        }
    }
}

extension JumpCondition: CustomDebugStringConvertible {

    var debugDescription: String {
        switch self {
        case .NZ: return "NZ"
        case .Z: return "Z"
        case .NC: return "NC"
        case .C: return "C"
        }
    }
}
