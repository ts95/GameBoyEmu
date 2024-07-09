//
//  GameBoyCPU.swift
//  GameBoyEmu
//
//  Created by Toni Sucic on 02/07/2024.
//

import Foundation

enum FlagBit: UInt8 {
    case zero           = 0b10000000  // Zero flag (1 << 7)
    case subtraction    = 0b01000000  // Subtraction flag (1 << 6)
    case halfCarry      = 0b00100000  // Half Carry flag (1 << 5)
    case carry          = 0b00010000  // Carry flag (1 << 4)
}

/// Swift implementation of the custom 8-bit Sharp LR35902 processor of the Game Boy.
/// The processor operates at approximately 4.19 MHz and uses the little endian layout.
class GameBoyCPU<Memory: MemoryAddressInterface> {

    // MARK: CPU state

    var isClockHalted = false
    var isClockStopped = false
    var isInterruptMasterEnabled = false {
        didSet {
            memory[0xFFFF] = isInterruptMasterEnabled ? 1 : 0
        }
    }

    // MARK: General-purpose registers

    /// Accumulator register
    var a: UInt8 = 0
    var b: UInt8 = 0
    var c: UInt8 = 0
    var d: UInt8 = 0
    var e: UInt8 = 0
    /// Flags register
    var f: UInt8 = 0
    var h: UInt8 = 0
    var l: UInt8 = 0

    // MARK: Special-purpose registers

    /// Stack pointer
    var sp: UInt16 = 0xFFFE
    /// Program counter
    var pc: UInt16 = 0x0100

    // MARK: Combined registers (16-bit register pairs)

    var af: UInt16 {
        get {
            return (UInt16(a) << 8) | UInt16(f)
        }
        set {
            a = UInt8((newValue >> 8) & 0xFF)
            f = UInt8(newValue & 0xFF)
        }
    }

    var bc: UInt16 {
        get {
            return (UInt16(b) << 8) | UInt16(c)
        }
        set {
            b = UInt8((newValue >> 8) & 0xFF)
            c = UInt8(newValue & 0xFF)
        }
    }

    var de: UInt16 {
        get {
            return (UInt16(d) << 8) | UInt16(e)
        }
        set {
            d = UInt8((newValue >> 8) & 0xFF)
            e = UInt8(newValue & 0xFF)
        }
    }

    var hl: UInt16 {
        get {
            return (UInt16(h) << 8) | UInt16(l)
        }
        set {
            h = UInt8((newValue >> 8) & 0xFF)
            l = UInt8(newValue & 0xFF)
        }
    }

    // MARK: Memory

    var memory: Memory

    // MARK: - Initializer

    init(memory: Memory) {
        self.memory = memory
    }

    // MARK: - Methods

    func set(flag: FlagBit) {
        f |= flag.rawValue
    }

    func clear(flag: FlagBit) {
        f &= ~flag.rawValue
    }

    func isSet(flag: FlagBit) -> Bool {
        (f & flag.rawValue) != 0
    }

    func setRegister(_ register: CPURegister, to value: UInt8) {
        switch register {
        case .A: a = value
        case .B: b = value
        case .C: c = value
        case .D: d = value
        case .E: e = value
        case .H: h = value
        case .L: l = value
        case .F: f = value
        }
    }

    func getRegister(_ register: CPURegister) -> UInt8 {
        switch register {
        case .A: return a
        case .B: return b
        case .C: return c
        case .D: return d
        case .E: return e
        case .H: return h
        case .L: return l
        case .F: return f
        }
    }

    func setRegisterPair(_ high: CPURegister, _ low: CPURegister, to value: UInt16) {
        setRegister(high, to: UInt8((value >> 8) & 0xFF))
        setRegister(low, to: UInt8(value & 0xFF))
    }

    func getRegisterPair(_ high: CPURegister, _ low: CPURegister) -> UInt16 {
        return (UInt16(getRegister(high)) << 8) | UInt16(getRegister(low))
    }

    func addToA(_ value: UInt8, withCarry: Bool = false) {
        let carry: UInt8 = withCarry && isSet(flag: .carry) ? 1 : 0
        let halfCarry = ((a & 0xF) + (value & 0xF) + carry) > 0xF
        let fullCarry = UInt16(a) + UInt16(value) + UInt16(carry) > 0xFF
        let result = a &+ value &+ carry

        a = result

        clear(flag: .subtraction)
        halfCarry ? set(flag: .halfCarry) : clear(flag: .halfCarry)
        fullCarry ? set(flag: .carry) : clear(flag: .carry)
        result == 0 ? set(flag: .zero) : clear(flag: .zero)
    }

    func subFromA(_ value: UInt8, withCarry: Bool = false) {
        let carry: UInt8 = withCarry && isSet(flag: .carry) ? 1 : 0
        let halfCarry = (a & 0xF) < (value & 0xF) + carry
        let fullCarry = Int(a) - Int(value) - Int(carry) < 0
        let result = a &- value &- carry

        a = result

        set(flag: .subtraction)
        halfCarry ? set(flag: .halfCarry) : clear(flag: .halfCarry)
        fullCarry ? set(flag: .carry) : clear(flag: .carry)
        result == 0 ? set(flag: .zero) : clear(flag: .zero)
    }

    func compareA(with value: UInt8) {
        let halfCarry = (a & 0xF) < (value & 0xF)
        let fullCarry = a < value
        let result = a &- value

        set(flag: .subtraction)
        halfCarry ? set(flag: .halfCarry) : clear(flag: .halfCarry)
        fullCarry ? set(flag: .carry) : clear(flag: .carry)
        result == 0 ? set(flag: .zero) : clear(flag: .zero)
    }

    func checkCondition(_ condition: JumpCondition) -> Bool {
        switch condition {
        case .NZ: return !isSet(flag: .zero)
        case .Z:  return isSet(flag: .zero)
        case .NC: return !isSet(flag: .carry)
        case .C:  return isSet(flag: .carry)
        }
    }

    func fetchWord() -> UInt16 {
        let low = memory[Int(pc)]
        pc += 1
        let high = memory[Int(pc)]
        pc += 1
        return UInt16(high) << 8 | UInt16(low)
    }

    func pushWord(_ value: UInt16) {
        sp -= 1
        memory[Int(sp)] = UInt8((value >> 8) & 0xFF)
        sp -= 1
        memory[Int(sp)] = UInt8(value & 0xFF)
    }

    func popWord() -> UInt16 {
        let low = memory[Int(sp)]
        sp += 1
        let high = memory[Int(sp)]
        sp += 1
        return UInt16(high) << 8 | UInt16(low)
    }

    func step() async throws {
        let opcode = memory[Int(pc)]
        pc += 1

        let instruction: CPUInstruction

        if opcode == 0xCB {
            let cbOpcode = memory[Int(pc)]
            pc += 1

            instruction = getInstruction(opcode: cbOpcode, isCBPrefixed: true)
        } else {
            instruction = getInstruction(opcode: opcode)
        }

        let tCycles = execute(instruction: instruction)
        let duration = UInt64(tCycles) * 238 // Each T cycle is 238 nanoseconds

        try await Task.sleep(nanoseconds: duration)

        print("\(UInt64(Date().timeIntervalSince1970 * 100_000)): executed \(instruction)")
    }

    func execute(instruction: CPUInstruction) -> Int {
        guard !isClockHalted else {
            return 4
        }

        switch instruction {
        case .loadRegister(let dest, let src):
            setRegister(dest, to: getRegister(src))
            return instruction.cycles.count()

        case .loadRegisterFromImmediate(let dest):
            let value = memory[Int(pc)]
            pc += 1
            setRegister(dest, to: value)
            return instruction.cycles.count()

        case .loadRegisterFromAddressHL(let dest):
            let address = hl
            let value = memory[Int(address)]
            setRegister(dest, to: value)
            return instruction.cycles.count()

        case .loadAddressHLFromRegister(let src):
            let address = hl
            let value = getRegister(src)
            memory[Int(address)] = value
            return instruction.cycles.count()

        case .loadAddressHLFromImmediate:
            let address = hl
            let value = memory[Int(pc)]
            pc += 1
            memory[Int(address)] = value
            return instruction.cycles.count()

        case .loadAFromAddressBC:
            a = memory[Int(bc)]
            return instruction.cycles.count()

        case .loadAFromAddressDE:
            a = memory[Int(de)]
            return instruction.cycles.count()

        case .loadAddressBCFromA:
            memory[Int(bc)] = a
            return instruction.cycles.count()

        case .loadAddressDEFromA:
            memory[Int(de)] = a
            return instruction.cycles.count()

        case .loadAFromAddressNN:
            let address = fetchWord()
            a = memory[Int(address)]
            return instruction.cycles.count()

        case .loadAddressNNFromA:
            let address = fetchWord()
            memory[Int(address)] = a
            return instruction.cycles.count()

        case .loadAFromAddressFF00PlusC:
            let address = 0xFF00 + UInt16(c)
            a = memory[Int(address)]
            return instruction.cycles.count()

        case .loadAddressFF00PlusCFromA:
            let address = 0xFF00 + UInt16(c)
            memory[Int(address)] = a
            return instruction.cycles.count()

        case .loadAFromAddressFF00PlusN:
            let address = 0xFF00 + UInt16(memory[Int(pc)])
            pc += 1
            a = memory[Int(address)]
            return instruction.cycles.count()

        case .loadAddressFF00PlusNFromA:
            let address = 0xFF00 + UInt16(memory[Int(pc)])
            pc += 1
            memory[Int(address)] = a
            return instruction.cycles.count()

        case .loadAFromAddressHLAndDecrement:
            a = memory[Int(hl)]
            hl -= 1
            return instruction.cycles.count()

        case .loadAddressHLAndDecrementFromA:
            memory[Int(hl)] = a
            hl -= 1
            return instruction.cycles.count()

        case .loadAFromAddressHLAndIncrement:
            a = memory[Int(hl)]
            hl += 1
            return instruction.cycles.count()

        case .loadAddressHLAndIncrementFromA:
            memory[Int(hl)] = a
            hl += 1
            return instruction.cycles.count()

        case .loadRegisterPairFromImmediate(let high, let low):
            let value = fetchWord()
            setRegisterPair(high, low, to: value)
            return instruction.cycles.count()

        case .loadAddressNNFromSP:
            let address = fetchWord()
            memory[Int(address)] = UInt8(sp & 0xFF)
            memory[Int(address + 1)] = UInt8((sp >> 8) & 0xFF)
            return instruction.cycles.count()

        case .loadSPFromHL:
            sp = hl
            return instruction.cycles.count()

        case .pushRegisterPair(let high, let low):
            pushWord(getRegisterPair(high, low))
            return instruction.cycles.count()

        case .popRegisterPair(let high, let low):
            setRegisterPair(high, low, to: popWord())
            return instruction.cycles.count()

        case .loadHLFromSPPlusE:
            let offset = Int8(bitPattern: memory[Int(pc)])
            pc += 1
            let result = Int(sp) + Int(offset)
            clear(flag: .zero)
            clear(flag: .subtraction)
            if (sp & 0xF) + (UInt16(offset) & 0xF) > 0xF {
                set(flag: .halfCarry)
            } else {
                clear(flag: .halfCarry)
            }
            if (sp & 0xFF) + UInt16(offset) > 0xFF {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            hl = UInt16(result & 0xFFFF)
            return instruction.cycles.count()

        case .addAWithRegister(let src):
            let value = getRegister(src)
            addToA(value)
            return instruction.cycles.count()

        case .addAWithAddressHL:
            let value = memory[Int(hl)]
            addToA(value)
            return instruction.cycles.count()

        case .addAWithImmediate:
            let value = memory[Int(pc)]
            pc += 1
            addToA(value)
            return instruction.cycles.count()

        case .addAWithCarryRegister(let src):
            let value = getRegister(src)
            addToA(value, withCarry: true)
            return instruction.cycles.count()

        case .addAWithCarryAddressHL:
            let value = memory[Int(hl)]
            addToA(value, withCarry: true)
            return instruction.cycles.count()

        case .addAWithCarryImmediate:
            let value = memory[Int(pc)]
            pc += 1
            addToA(value, withCarry: true)
            return instruction.cycles.count()

        case .subtractAWithRegister(let src):
            let value = getRegister(src)
            subFromA(value)
            return instruction.cycles.count()

        case .subtractAWithAddressHL:
            let value = memory[Int(hl)]
            subFromA(value)
            return instruction.cycles.count()

        case .subtractAWithImmediate:
            let value = memory[Int(pc)]
            pc += 1
            subFromA(value)
            return instruction.cycles.count()

        case .subtractAWithCarryRegister(let src):
            let value = getRegister(src)
            subFromA(value, withCarry: true)
            return instruction.cycles.count()

        case .subtractAWithCarryAddressHL:
            let value = memory[Int(hl)]
            subFromA(value, withCarry: true)
            return instruction.cycles.count()

        case .subtractAWithCarryImmediate:
            let value = memory[Int(pc)]
            pc += 1
            subFromA(value, withCarry: true)
            return instruction.cycles.count()

        case .compareAWithRegister(let src):
            let value = getRegister(src)
            compareA(with: value)
            return instruction.cycles.count()

        case .compareAWithAddressHL:
            let value = memory[Int(hl)]
            compareA(with: value)
            return instruction.cycles.count()

        case .compareAWithImmediate:
            let value = memory[Int(pc)]
            pc += 1
            compareA(with: value)
            return instruction.cycles.count()

        case .incrementRegister(let dest):
            let value = getRegister(dest)
            let result = value &+ 1
            setRegister(dest, to: result)
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            if (value & 0xF) + 1 > 0xF {
                set(flag: .halfCarry)
            } else {
                clear(flag: .halfCarry)
            }
            return instruction.cycles.count()

        case .incrementAddressHL:
            let address = hl
            let value = memory[Int(address)]
            let result = value &+ 1
            memory[Int(address)] = result
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            if (value & 0xF) + 1 > 0xF {
                set(flag: .halfCarry)
            } else {
                clear(flag: .halfCarry)
            }
            return instruction.cycles.count()

        case .decrementRegister(let dest):
            let value = getRegister(dest)
            let result = value &- 1
            setRegister(dest, to: result)
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            set(flag: .subtraction)
            if (value & 0xF) == 0 {
                set(flag: .halfCarry)
            } else {
                clear(flag: .halfCarry)
            }
            return instruction.cycles.count()

        case .decrementAddressHL:
            let address = hl
            let value = memory[Int(address)]
            let result = value &- 1
            memory[Int(address)] = result
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            set(flag: .subtraction)
            if (value & 0xF) == 0 {
                set(flag: .halfCarry)
            } else {
                clear(flag: .halfCarry)
            }
            return instruction.cycles.count()

        case .bitwiseAndWithRegister(let src):
            let value = getRegister(src)
            a &= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            set(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseAndWithAddressHL:
            let value = memory[Int(hl)]
            a &= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            set(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseAndWithImmediate:
            let value = memory[Int(pc)]
            pc += 1
            a &= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            set(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseOrWithRegister(let src):
            let value = getRegister(src)
            a |= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseOrWithAddressHL:
            let value = memory[Int(hl)]
            a |= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseOrWithImmediate:
            let value = memory[Int(pc)]
            pc += 1
            a |= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseXorWithRegister(let src):
            let value = getRegister(src)
            a ^= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseXorWithAddressHL:
            let value = memory[Int(hl)]
            a ^= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .bitwiseXorWithImmediate:
            let value = memory[Int(pc)]
            pc += 1
            a ^= value
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .complementCarryFlag:
            if isSet(flag: .carry) {
                clear(flag: .carry)
            } else {
                set(flag: .carry)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .setCarryFlag:
            set(flag: .carry)
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .decimalAdjustAccumulator:
            var adjust: UInt8 = 0
            if isSet(flag: .halfCarry) || (!isSet(flag: .subtraction) && (a & 0xF) > 9) {
                adjust = 0x06
            }
            if isSet(flag: .carry) || (!isSet(flag: .subtraction) && a > 0x99) {
                adjust |= 0x60
                set(flag: .carry)
            }
            if isSet(flag: .subtraction) {
                a = a &- adjust
            } else {
                a = a &+ adjust
            }
            clear(flag: .halfCarry)
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            return instruction.cycles.count()

        case .complementAccumulator:
            a = ~a
            set(flag: .subtraction)
            set(flag: .halfCarry)
            return instruction.cycles.count()

        case .incrementRegisterPair(let high, let low):
            let value = getRegisterPair(high, low) &+ 1
            setRegisterPair(high, low, to: value)
            return instruction.cycles.count()

        case .decrementRegisterPair(let high, let low):
            let value = getRegisterPair(high, low) &- 1
            setRegisterPair(high, low, to: value)
            return instruction.cycles.count()

        case .addHLWithRegisterPair(let high, let low):
            let value = getRegisterPair(high, low)
            let result = hl &+ value
            clear(flag: .subtraction)
            if ((hl & 0xFFF) + (value & 0xFFF)) > 0xFFF {
                set(flag: .halfCarry)
            } else {
                clear(flag: .halfCarry)
            }
            if (UInt32(hl) + UInt32(value)) > 0xFFFF {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            hl = result
            return instruction.cycles.count()

        case .addSPWithE:
            let offset = Int8(bitPattern: memory[Int(pc)])
            pc += 1
            let result = Int(sp) + Int(offset)
            clear(flag: .zero)
            clear(flag: .subtraction)
            if (sp & 0xF) + (UInt16(offset) & 0xF) > 0xF {
                set(flag: .halfCarry)
            } else {
                clear(flag: .halfCarry)
            }
            if (sp & 0xFF) + UInt16(offset) > 0xFF {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            sp = UInt16(result & 0xFFFF)
            return instruction.cycles.count()

        case .rotateLeftCircularAccumulator:
            let carry = a & 0x80
            a = (a << 1) | (carry >> 7)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateRightCircularAccumulator:
            let carry = a & 0x01
            a = (a >> 1) | (carry << 7)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateLeftAccumulator:
            let carry = a & 0x80
            a = (a << 1) | (isSet(flag: .carry) ? 1 : 0)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateRightAccumulator:
            let carry = a & 0x01
            a = (a >> 1) | (isSet(flag: .carry) ? 0x80 : 0)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if a == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateLeftCircularRegister(let dest):
            let value = getRegister(dest)
            let carry = value & 0x80
            let result = (value << 1) | (carry >> 7)
            setRegister(dest, to: result)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateLeftCircularAddressHL:
            let value = memory[Int(hl)]
            let carry = value & 0x80
            let result = (value << 1) | (carry >> 7)
            memory[Int(hl)] = result
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateRightCircularRegister(let dest):
            let value = getRegister(dest)
            let carry = value & 0x01
            let result = (value >> 1) | (carry << 7)
            setRegister(dest, to: result)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateRightCircularAddressHL:
            let value = memory[Int(hl)]
            let carry = value & 0x01
            let result = (value >> 1) | (carry << 7)
            memory[Int(hl)] = result
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateLeftRegister(let dest):
            let value = getRegister(dest)
            let carry = value & 0x80
            let result = (value << 1) | (isSet(flag: .carry) ? 1 : 0)
            setRegister(dest, to: result)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateLeftAddressHL:
            let value = memory[Int(hl)]
            let carry = value & 0x80
            let result = (value << 1) | (isSet(flag: .carry) ? 1 : 0)
            memory[Int(hl)] = result
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateRightRegister(let dest):
            let value = getRegister(dest)
            let carry = value & 0x01
            let result = (value >> 1) | (isSet(flag: .carry) ? 0x80 : 0)
            setRegister(dest, to: result)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .rotateRightAddressHL:
            let value = memory[Int(hl)]
            let carry = value & 0x01
            let result = (value >> 1) | (isSet(flag: .carry) ? 0x80 : 0)
            memory[Int(hl)] = result
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .shiftLeftArithmeticRegister(let dest):
            let value = getRegister(dest)
            let carry = value & 0x80
            let result = value << 1
            setRegister(dest, to: result)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .shiftLeftArithmeticAddressHL:
            let value = memory[Int(hl)]
            let carry = value & 0x80
            let result = value << 1
            memory[Int(hl)] = result
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .shiftRightArithmeticRegister(let dest):
            let value = getRegister(dest)
            let carry = value & 0x01
            let result = (value >> 1) | (value & 0x80)
            setRegister(dest, to: result)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            set(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .shiftRightArithmeticAddressHL:
            let value = memory[Int(hl)]
            let carry = value & 0x01
            let result = (value >> 1) | (value & 0x80)
            memory[Int(hl)] = result
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            set(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .swapNibblesRegister(let dest):
            let value = getRegister(dest)
            let result = (value >> 4) | (value << 4)
            setRegister(dest, to: result)
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .swapNibblesAddressHL:
            let value = memory[Int(hl)]
            let result = (value >> 4) | (value << 4)
            memory[Int(hl)] = result
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            clear(flag: .carry)
            return instruction.cycles.count()

        case .shiftRightLogicalRegister(let dest):
            let value = getRegister(dest)
            let carry = value & 0x01
            let result = value >> 1
            setRegister(dest, to: result)
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .shiftRightLogicalAddressHL:
            let value = memory[Int(hl)]
            let carry = value & 0x01
            let result = value >> 1
            memory[Int(hl)] = result
            if carry != 0 {
                set(flag: .carry)
            } else {
                clear(flag: .carry)
            }
            if result == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            clear(flag: .halfCarry)
            return instruction.cycles.count()

        case .testBitRegister(let bit, let dest):
            let value = getRegister(dest)
            if (value & (1 << bit)) == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            set(flag: .halfCarry)
            return instruction.cycles.count()

        case .testBitAddressHL(let bit):
            let value = memory[Int(hl)]
            if (value & (1 << bit)) == 0 {
                set(flag: .zero)
            } else {
                clear(flag: .zero)
            }
            clear(flag: .subtraction)
            set(flag: .halfCarry)
            return instruction.cycles.count()

        case .resetBitRegister(let bit, let dest):
            var value = getRegister(dest)
            value &= ~(1 << bit)
            setRegister(dest, to: value)
            return instruction.cycles.count()

        case .resetBitAddressHL(let bit):
            var value = memory[Int(hl)]
            value &= ~(1 << bit)
            memory[Int(hl)] = value
            return instruction.cycles.count()

        case .setBitRegister(let bit, let dest):
            var value = getRegister(dest)
            value |= (1 << bit)
            setRegister(dest, to: value)
            return instruction.cycles.count()

        case .setBitAddressHL(let bit):
            var value = memory[Int(hl)]
            value |= (1 << bit)
            memory[Int(hl)] = value
            return instruction.cycles.count()

        case .jump(let address):
            pc = address
            return instruction.cycles.count()

        case .jumpToHL:
            pc = hl
            return instruction.cycles.count()

        case .jumpConditional(let condition, let address):
            if checkCondition(condition) {
                pc = address
                return instruction.cycles.count(conditionMet: true)
            } else {
                return instruction.cycles.count()
            }

        case .relativeJump(let offset):
            pc = UInt16(Int(pc) + Int(offset))
            return instruction.cycles.count()

        case .relativeJumpConditional(let condition, let offset):
            if checkCondition(condition) {
                pc = UInt16(Int(pc) + Int(offset))
                return instruction.cycles.count(conditionMet: true)
            } else {
                return instruction.cycles.count()
            }

        case .callFunction(let address):
            pushWord(pc)
            pc = address
            return instruction.cycles.count()

        case .callFunctionConditional(let condition, let address):
            if checkCondition(condition) {
                pushWord(pc)
                pc = address
                return instruction.cycles.count(conditionMet: true)
            } else {
                return instruction.cycles.count()
            }

        case .returnFromFunction:
            pc = popWord()
            return instruction.cycles.count()

        case .returnFromFunctionConditional(let condition):
            if checkCondition(condition) {
                pc = popWord()
                return instruction.cycles.count(conditionMet: true)
            } else {
                return instruction.cycles.count()
            }

        case .returnFromInterruptHandler:
            pc = popWord()
            isInterruptMasterEnabled = true
            return instruction.cycles.count()

        case .restartCallFunction(let address):
            pushWord(pc)
            pc = UInt16(address)
            return instruction.cycles.count()

        case .haltSystemClock:
            // Halts CPU operation until an interrupt occurs
            isClockHalted = true
            return instruction.cycles.count()

        case .stopSystemAndMainClocks:
            // Stops both the system clock and the main clock
            isClockStopped = true
            return instruction.cycles.count()

        case .disableInterrupts:
            isClockHalted = false
            isInterruptMasterEnabled = false
            return instruction.cycles.count()

        case .enableInterrupts:
            isInterruptMasterEnabled = true
            return instruction.cycles.count()

        case .noOperation:
            return instruction.cycles.count()
        }
    }

    func getInstruction(opcode: UInt8, isCBPrefixed: Bool = false) -> CPUInstruction {
        if isCBPrefixed {
            switch opcode {
            case 0x00...0x07:
                return .rotateLeftCircularRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x06:
                return .rotateLeftCircularAddressHL
            case 0x08...0x0F:
                return .rotateRightCircularRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x0E:
                return .rotateRightCircularAddressHL
            case 0x10...0x17:
                return .rotateLeftRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x16:
                return .rotateLeftAddressHL
            case 0x18...0x1F:
                return .rotateRightRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x1E:
                return .rotateRightAddressHL
            case 0x20...0x27:
                return .shiftLeftArithmeticRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x26:
                return .shiftLeftArithmeticAddressHL
            case 0x28...0x2F:
                return .shiftRightArithmeticRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x2E:
                return .shiftRightArithmeticAddressHL
            case 0x30...0x37:
                return .swapNibblesRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x36:
                return .swapNibblesAddressHL
            case 0x38...0x3F:
                return .shiftRightLogicalRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x3E:
                return .shiftRightLogicalAddressHL
            case 0x40...0x7F:
                let bit = (opcode >> 3) & 0x07
                return .testBitRegister(bit, CPURegister(rawValue: opcode & 0x07)!)
            case 0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E, 0x76, 0x7E:
                let bit = (opcode >> 3) & 0x07
                return .testBitAddressHL(bit)
            case 0x80...0xBF:
                let bit = (opcode >> 3) & 0x07
                return .resetBitRegister(bit, CPURegister(rawValue: opcode & 0x07)!)
            case 0x86, 0x8E, 0x96, 0x9E, 0xA6, 0xAE, 0xB6, 0xBE:
                let bit = (opcode >> 3) & 0x07
                return .resetBitAddressHL(bit)
            case 0xC0...0xFF:
                let bit = (opcode >> 3) & 0x07
                return .setBitRegister(bit, CPURegister(rawValue: opcode & 0x07)!)
            case 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE:
                let bit = (opcode >> 3) & 0x07
                return .setBitAddressHL(bit)
            default:
                fatalError("Unsupported CB-prefixed opcode: \(String(format: "%02X", opcode))")
            }
        } else {
            switch opcode {
            case 0x40...0x7F:
                let dest = CPURegister(rawValue: (opcode >> 3) & 0x07)!
                let src = CPURegister(rawValue: opcode & 0x07)!
                return .loadRegister(dest, src)
            case 0x06:
                return .loadRegisterFromImmediate(.B)
            case 0x0E:
                return .loadRegisterFromImmediate(.C)
            case 0x16:
                return .loadRegisterFromImmediate(.D)
            case 0x1E:
                return .loadRegisterFromImmediate(.E)
            case 0x26:
                return .loadRegisterFromImmediate(.H)
            case 0x2E:
                return .loadRegisterFromImmediate(.L)
            case 0x3E:
                return .loadRegisterFromImmediate(.A)
            case 0x46:
                return .loadRegisterFromAddressHL(.B)
            case 0x4E:
                return .loadRegisterFromAddressHL(.C)
            case 0x56:
                return .loadRegisterFromAddressHL(.D)
            case 0x5E:
                return .loadRegisterFromAddressHL(.E)
            case 0x66:
                return .loadRegisterFromAddressHL(.H)
            case 0x6E:
                return .loadRegisterFromAddressHL(.L)
            case 0x7E:
                return .loadRegisterFromAddressHL(.A)
            case 0x70:
                return .loadAddressHLFromRegister(.B)
            case 0x71:
                return .loadAddressHLFromRegister(.C)
            case 0x72:
                return .loadAddressHLFromRegister(.D)
            case 0x73:
                return .loadAddressHLFromRegister(.E)
            case 0x74:
                return .loadAddressHLFromRegister(.H)
            case 0x75:
                return .loadAddressHLFromRegister(.L)
            case 0x36:
                return .loadAddressHLFromImmediate
            case 0x0A:
                return .loadAFromAddressBC
            case 0x1A:
                return .loadAFromAddressDE
            case 0x02:
                return .loadAddressBCFromA
            case 0x12:
                return .loadAddressDEFromA
            case 0xFA:
                return .loadAFromAddressNN
            case 0xEA:
                return .loadAddressNNFromA
            case 0xF2:
                return .loadAFromAddressFF00PlusC
            case 0xE2:
                return .loadAddressFF00PlusCFromA
            case 0xF0:
                return .loadAFromAddressFF00PlusN
            case 0xE0:
                return .loadAddressFF00PlusNFromA
            case 0x3A:
                return .loadAFromAddressHLAndDecrement
            case 0x32:
                return .loadAddressHLAndDecrementFromA
            case 0x2A:
                return .loadAFromAddressHLAndIncrement
            case 0x22:
                return .loadAddressHLAndIncrementFromA
            case 0x01:
                return .loadRegisterPairFromImmediate(.B, .C)
            case 0x11:
                return .loadRegisterPairFromImmediate(.D, .E)
            case 0x21:
                return .loadRegisterPairFromImmediate(.H, .L)
            case 0x31:
                return .loadRegisterPairFromImmediate(.A, .F)
            case 0x08:
                return .loadAddressNNFromSP
            case 0xF9:
                return .loadSPFromHL
            case 0xC5:
                return .pushRegisterPair(.B, .C)
            case 0xD5:
                return .pushRegisterPair(.D, .E)
            case 0xE5:
                return .pushRegisterPair(.H, .L)
            case 0xF5:
                return .pushRegisterPair(.A, .F)
            case 0xC1:
                return .popRegisterPair(.B, .C)
            case 0xD1:
                return .popRegisterPair(.D, .E)
            case 0xE1:
                return .popRegisterPair(.H, .L)
            case 0xF1:
                return .popRegisterPair(.A, .F)
            case 0xF8:
                return .loadHLFromSPPlusE
            case 0x80...0x87:
                return .addAWithRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x86:
                return .addAWithAddressHL
            case 0xC6:
                return .addAWithImmediate
            case 0x88...0x8F:
                return .addAWithCarryRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x8E:
                return .addAWithCarryAddressHL
            case 0xCE:
                return .addAWithCarryImmediate
            case 0x90...0x97:
                return .subtractAWithRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x96:
                return .subtractAWithAddressHL
            case 0xD6:
                return .subtractAWithImmediate
            case 0x98...0x9F:
                return .subtractAWithCarryRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0x9E:
                return .subtractAWithCarryAddressHL
            case 0xDE:
                return .subtractAWithCarryImmediate
            case 0xB8...0xBF:
                return .compareAWithRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0xBE:
                return .compareAWithAddressHL
            case 0xFE:
                return .compareAWithImmediate
            case 0x04:
                return .incrementRegister(.B)
            case 0x0C:
                return .incrementRegister(.C)
            case 0x14:
                return .incrementRegister(.D)
            case 0x1C:
                return .incrementRegister(.E)
            case 0x24:
                return .incrementRegister(.H)
            case 0x2C:
                return .incrementRegister(.L)
            case 0x3C:
                return .incrementRegister(.A)
            case 0x34:
                return .incrementAddressHL
            case 0x05:
                return .decrementRegister(.B)
            case 0x0D:
                return .decrementRegister(.C)
            case 0x15:
                return .decrementRegister(.D)
            case 0x1D:
                return .decrementRegister(.E)
            case 0x25:
                return .decrementRegister(.H)
            case 0x2D:
                return .decrementRegister(.L)
            case 0x3D:
                return .decrementRegister(.A)
            case 0x35:
                return .decrementAddressHL
            case 0xA0...0xA7:
                return .bitwiseAndWithRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0xA6:
                return .bitwiseAndWithAddressHL
            case 0xE6:
                return .bitwiseAndWithImmediate
            case 0xB0...0xB7:
                return .bitwiseOrWithRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0xB6:
                return .bitwiseOrWithAddressHL
            case 0xF6:
                return .bitwiseOrWithImmediate
            case 0xA8...0xAF:
                return .bitwiseXorWithRegister(CPURegister(rawValue: opcode & 0x07)!)
            case 0xAE:
                return .bitwiseXorWithAddressHL
            case 0xEE:
                return .bitwiseXorWithImmediate
            case 0x3F:
                return .complementCarryFlag
            case 0x37:
                return .setCarryFlag
            case 0x27:
                return .decimalAdjustAccumulator
            case 0x2F:
                return .complementAccumulator
            case 0x03:
                return .incrementRegisterPair(.B, .C)
            case 0x13:
                return .incrementRegisterPair(.D, .E)
            case 0x23:
                return .incrementRegisterPair(.H, .L)
            case 0x33:
                return .incrementRegisterPair(.A, .F)
            case 0x0B:
                return .decrementRegisterPair(.B, .C)
            case 0x1B:
                return .decrementRegisterPair(.D, .E)
            case 0x2B:
                return .decrementRegisterPair(.H, .L)
            case 0x3B:
                return .decrementRegisterPair(.A, .F)
            case 0x09:
                return .addHLWithRegisterPair(.B, .C)
            case 0x19:
                return .addHLWithRegisterPair(.D, .E)
            case 0x29:
                return .addHLWithRegisterPair(.H, .L)
            case 0x39:
                return .addHLWithRegisterPair(.A, .F)
            case 0xE8:
                return .addSPWithE
            case 0x07:
                return .rotateLeftCircularAccumulator
            case 0x0F:
                return .rotateRightCircularAccumulator
            case 0x17:
                return .rotateLeftAccumulator
            case 0x1F:
                return .rotateRightAccumulator
            case 0xC3:
                let address = UInt16(memory[Int(pc)]) | (UInt16(memory[Int(pc) + 1]) << 8)
                pc += 2
                return .jump(address)
            case 0xE9:
                return .jumpToHL
            case 0xC2, 0xCA, 0xD2, 0xDA:
                let address = UInt16(memory[Int(pc)]) | (UInt16(memory[Int(pc) + 1]) << 8)
                pc += 2
                let condition = JumpCondition(rawValue: (opcode >> 3) & 0x03)!
                return .jumpConditional(condition, address)
            case 0x18:
                let offset = Int8(bitPattern: memory[Int(pc)])
                pc += 1
                return .relativeJump(offset)
            case 0x20, 0x28, 0x30, 0x38:
                let offset = Int8(bitPattern: memory[Int(pc)])
                pc += 1
                let condition = JumpCondition(rawValue: (opcode >> 3) & 0x03)!
                return .relativeJumpConditional(condition, offset)
            case 0xCD:
                let address = UInt16(memory[Int(pc)]) | (UInt16(memory[Int(pc) + 1]) << 8)
                pc += 2
                return .callFunction(address)
            case 0xC4, 0xCC, 0xD4, 0xDC:
                let address = UInt16(memory[Int(pc)]) | (UInt16(memory[Int(pc) + 1]) << 8)
                pc += 2
                let condition = JumpCondition(rawValue: (opcode >> 3) & 0x03)!
                return .callFunctionConditional(condition, address)
            case 0xC9:
                return .returnFromFunction
            case 0xC0, 0xC8, 0xD0, 0xD8:
                let condition = JumpCondition(rawValue: (opcode >> 3) & 0x03)!
                return .returnFromFunctionConditional(condition)
            case 0xD9:
                return .returnFromInterruptHandler
            case 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF:
                return .restartCallFunction(opcode & 0x38)
            case 0x76:
                return .haltSystemClock
            case 0x10:
                return .stopSystemAndMainClocks
            case 0xF3:
                return .disableInterrupts
            case 0xFB:
                return .enableInterrupts
            case 0x00:
                return .noOperation
            default:
                fatalError("Unsupported opcode: \(String(format: "%02X", opcode))")
            }
        }
    }
}
