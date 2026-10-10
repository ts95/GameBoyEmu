//
//  GameBoyAPU.swift
//  GameBoyEmu
//

import Foundation

/// The Game Boy Audio Processing Unit (APU), controlled through the registers at 0xFF10-0xFF3F.
///
/// Like the PPU and the timer, the APU is an independent machine that is advanced by the number
/// of cycles the CPU just spent. It has four sound channels, each producing a volume between
/// 0 and 15 at any instant:
///
/// 1. Pulse 1: a square wave whose pitch can slide up or down (the "sweep").
/// 2. Pulse 2: a square wave.
/// 3. Wave: plays back 32 four-bit samples the game stores at 0xFF30-0xFF3F.
/// 4. Noise: pseudo-random bits, used for drums and sound effects.
///
/// A game plays a note by writing a pitch and volume to a channel's registers and then setting
/// the "trigger" bit. From there the hardware shapes the note on its own: the envelope fades
/// the volume, the length counter cuts the note off, and the sweep bends the pitch.
final class GameBoyAPU {
    /// The number of stereo samples produced per second of emulated time.
    static let sampleRate = 48_000

    /// The mixed output, as interleaved left/right samples between -1 and 1.
    /// Whoever plays the audio takes the samples out of here once per frame.
    var pendingSamples: [Float] = []

    // MARK: - Channel building blocks

    /// Fades a channel's volume up or down, one step at a time.
    private struct Envelope {
        var initialVolume = 0
        var isIncreasing = false
        var period = 0 // In 1/64 s ticks. 0 means the volume stays where it is.
        var volume = 0
        var timer = 0

        /// A channel whose envelope register has all of its upper 5 bits clear is switched off.
        var isDACOn: Bool { initialVolume != 0 || isIncreasing }

        mutating func write(_ value: UInt8) {
            initialVolume = Int(value >> 4)
            isIncreasing = value & 0x08 != 0
            period = Int(value & 0x07)
        }

        mutating func trigger() {
            volume = initialVolume
            timer = period
        }

        mutating func clock() {
            guard period != 0 else { return }
            timer -= 1
            if timer <= 0 {
                timer = period
                if isIncreasing && volume < 15 {
                    volume += 1
                } else if !isIncreasing && volume > 0 {
                    volume -= 1
                }
            }
        }
    }

    private struct PulseChannel: LengthCounted {
        // Which of the 8 steps of the waveform are high, for 12.5%, 25%, 50% and 75% duty
        static let dutyPatterns: [UInt8] = [0b0000_0001, 0b1000_0001, 0b1000_0111, 0b0111_1110]

        var isEnabled = false
        var envelope = Envelope()
        var duty = 0
        var dutyPosition = 0
        var frequency = 0 // 11 bits. Higher means higher pitch: the tone is 131072 / (2048 - frequency) Hz
        var timer = 0
        var length = 0
        var isLengthEnabled = false

        // Sweep (only used by pulse 1)
        var sweepPeriod = 0
        var isSweepNegated = false
        var sweepShift = 0
        var sweepTimer = 0
        var isSweepEnabled = false
        var shadowFrequency = 0

        var output: Int {
            let isHigh = (PulseChannel.dutyPatterns[duty] >> (7 - dutyPosition)) & 1 != 0
            return isEnabled && isHigh ? envelope.volume : 0
        }

        mutating func advance(cycles: Int) {
            timer -= cycles
            while timer <= 0 {
                timer += (2048 - frequency) * 4
                dutyPosition = (dutyPosition + 1) & 7
            }
        }

        /// Handles a write to one of the channel's registers, NRx1 to NRx4.
        mutating func write(register: Int, value: UInt8) {
            switch register {
            case 1:
                duty = Int(value >> 6)
                length = 64 - Int(value & 0x3F)
            case 2:
                envelope.write(value)
                if !envelope.isDACOn {
                    isEnabled = false
                }
            case 3:
                frequency = (frequency & 0x700) | Int(value)
            default:
                frequency = (frequency & 0x0FF) | (Int(value & 0x07) << 8)
                isLengthEnabled = value & 0x40 != 0
                if value & 0x80 != 0 {
                    trigger()
                }
            }
        }

        mutating func trigger() {
            isEnabled = envelope.isDACOn
            if length == 0 {
                length = 64
            }
            timer = (2048 - frequency) * 4
            envelope.trigger()

            shadowFrequency = frequency
            sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod
            isSweepEnabled = sweepPeriod != 0 || sweepShift != 0
            if sweepShift != 0 {
                _ = sweptFrequency()
            }
        }

        /// The next frequency of the sweep. Sweeping past the highest pitch silences the channel.
        private mutating func sweptFrequency() -> Int {
            let delta = shadowFrequency >> sweepShift
            let newFrequency = isSweepNegated ? shadowFrequency - delta : shadowFrequency + delta
            if newFrequency > 2047 {
                isEnabled = false
            }
            return newFrequency
        }

        mutating func clockSweep() {
            sweepTimer -= 1
            guard sweepTimer <= 0 else { return }
            sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod

            if isSweepEnabled && sweepPeriod != 0 {
                let newFrequency = sweptFrequency()
                if newFrequency <= 2047 && sweepShift != 0 {
                    frequency = newFrequency
                    shadowFrequency = newFrequency
                    _ = sweptFrequency()
                }
            }
        }
    }

    private struct WaveChannel: LengthCounted {
        var isEnabled = false
        var isDACOn = false
        var volumeCode = 0 // 0 = mute, 1 = 100%, 2 = 50%, 3 = 25%
        var frequency = 0
        var timer = 0
        var position = 0 // Which of the 32 samples is playing
        var length = 0
        var isLengthEnabled = false

        mutating func advance(cycles: Int) {
            timer -= cycles
            while timer <= 0 {
                timer += (2048 - frequency) * 2
                position = (position + 1) & 31
            }
        }

        mutating func trigger() {
            isEnabled = isDACOn
            if length == 0 {
                length = 256
            }
            timer = (2048 - frequency) * 2
            position = 0
        }
    }

    private struct NoiseChannel: LengthCounted {
        var isEnabled = false
        var envelope = Envelope()
        var clockShift = 0
        var isShortMode = false // A 7-bit sequence instead of 15 bits, which sounds metallic
        var divisorCode = 0
        var timer = 0
        var length = 0
        var isLengthEnabled = false

        /// The linear-feedback shift register: each clock shifts it right and feeds the XOR of
        /// its two lowest bits back in at the top, which yields a long random-looking bit stream.
        var shiftRegister = 0x7FFF

        var period: Int { (divisorCode == 0 ? 8 : divisorCode * 16) << clockShift }

        var output: Int {
            isEnabled && shiftRegister & 1 == 0 ? envelope.volume : 0
        }

        mutating func advance(cycles: Int) {
            timer -= cycles
            while timer <= 0 {
                timer += period
                let bit = (shiftRegister ^ (shiftRegister >> 1)) & 1
                shiftRegister = (shiftRegister >> 1) | (bit << 14)
                if isShortMode {
                    shiftRegister = (shiftRegister & ~0x40) | (bit << 6)
                }
            }
        }

        mutating func trigger() {
            isEnabled = envelope.isDACOn
            if length == 0 {
                length = 64
            }
            timer = period
            shiftRegister = 0x7FFF
            envelope.trigger()
        }
    }

    // MARK: - State

    private var pulse1 = PulseChannel()
    private var pulse2 = PulseChannel()
    private var wave = WaveChannel()
    private var noise = NoiseChannel()

    /// The raw bytes last written to 0xFF10-0xFF3F. The wave channel's samples (0xFF30-0xFF3F),
    /// the master volume (NR50) and the panning (NR51) are used straight from here.
    private var registers = [UInt8](repeating: 0, count: 0x30)

    /// Bit 7 of NR52. Switching the APU off clears every register.
    private var isPoweredOn = true

    /// The frame sequencer ticks at 512 Hz and paces the length counters (256 Hz),
    /// the sweep (128 Hz) and the envelopes (64 Hz).
    private var frameSequencerCycles = 0
    private var frameSequencerStep = 0

    // Downsampling from one value per cycle to `sampleRate` values per second
    private var sampleClock = 0
    private var accumulatedLeft: Float = 0
    private var accumulatedRight: Float = 0
    private var accumulatedCycles = 0

    // The outputs go through a capacitor on real hardware, which removes the constant offset
    private var capacitorLeft: Float = 0
    private var capacitorRight: Float = 0

    /// Bits that don't exist or are write-only read back as 1, for NR10 (0xFF10) to NR51 (0xFF25)
    private static let readMasks: [UInt8] = [
        0x80, 0x3F, 0x00, 0xFF, 0xBF,
        0xFF, 0x3F, 0x00, 0xFF, 0xBF,
        0x7F, 0xFF, 0x9F, 0xFF, 0xBF,
        0xFF, 0xFF, 0x00, 0x00, 0xBF,
        0x00, 0x00,
    ]

    init() {
        // What the boot ROM leaves behind: full volume, all channels routed somewhere
        registers[0x14] = 0x77 // NR50
        registers[0x15] = 0xF3 // NR51
    }

    // MARK: - Registers

    /// Register access, by address (0xFF10-0xFF3F).
    subscript(address: Int) -> UInt8 {
        get {
            let index = address - 0xFF10
            switch address {
            case 0xFF26:
                // NR52: the power bit, plus one read-only "is playing" bit per channel
                return (isPoweredOn ? 0x80 : 0) | 0x70
                    | (pulse1.isEnabled ? 0x01 : 0) | (pulse2.isEnabled ? 0x02 : 0)
                    | (wave.isEnabled ? 0x04 : 0) | (noise.isEnabled ? 0x08 : 0)
            case 0xFF30...0xFF3F:
                return registers[index]
            default:
                return index < GameBoyAPU.readMasks.count ? registers[index] | GameBoyAPU.readMasks[index] : 0xFF
            }
        }
        set {
            let index = address - 0xFF10

            if address >= 0xFF30 {
                registers[index] = newValue // Wave samples stay writable while the power is off
                return
            }
            if address == 0xFF26 {
                isPoweredOn = newValue & 0x80 != 0
                if !isPoweredOn {
                    registers.replaceSubrange(0..<0x20, with: repeatElement(0, count: 0x20))
                    pulse1 = PulseChannel()
                    pulse2 = PulseChannel()
                    wave = WaveChannel()
                    noise = NoiseChannel()
                }
                return
            }
            guard isPoweredOn else {
                return
            }

            registers[index] = newValue

            switch address {
            case 0xFF10: // NR10: pulse 1 sweep
                pulse1.sweepPeriod = Int((newValue >> 4) & 0x07)
                pulse1.isSweepNegated = newValue & 0x08 != 0
                pulse1.sweepShift = Int(newValue & 0x07)
            case 0xFF11...0xFF14: // NR11-NR14
                pulse1.write(register: address - 0xFF10, value: newValue)
            case 0xFF16...0xFF19: // NR21-NR24
                pulse2.write(register: address - 0xFF15, value: newValue)

            case 0xFF1A: // NR30: wave channel on/off
                wave.isDACOn = newValue & 0x80 != 0
                if !wave.isDACOn {
                    wave.isEnabled = false
                }
            case 0xFF1B: // NR31
                wave.length = 256 - Int(newValue)
            case 0xFF1C: // NR32
                wave.volumeCode = Int((newValue >> 5) & 0x03)
            case 0xFF1D: // NR33
                wave.frequency = (wave.frequency & 0x700) | Int(newValue)
            case 0xFF1E: // NR34
                wave.frequency = (wave.frequency & 0x0FF) | (Int(newValue & 0x07) << 8)
                wave.isLengthEnabled = newValue & 0x40 != 0
                if newValue & 0x80 != 0 {
                    wave.trigger()
                }

            case 0xFF20: // NR41
                noise.length = 64 - Int(newValue & 0x3F)
            case 0xFF21: // NR42
                noise.envelope.write(newValue)
                if !noise.envelope.isDACOn {
                    noise.isEnabled = false
                }
            case 0xFF22: // NR43
                noise.clockShift = Int(newValue >> 4)
                noise.isShortMode = newValue & 0x08 != 0
                noise.divisorCode = Int(newValue & 0x07)
            case 0xFF23: // NR44
                noise.isLengthEnabled = newValue & 0x40 != 0
                if newValue & 0x80 != 0 {
                    noise.trigger()
                }

            default:
                break
            }
        }
    }

    // MARK: - Stepping

    /// Advances the APU by the given number of cycles, appending to `pendingSamples`
    /// whenever enough time has passed for another output sample.
    func step(cycles: Int) {
        if isPoweredOn {
            frameSequencerCycles += cycles
            while frameSequencerCycles >= 8192 { // 4194304 Hz / 8192 = 512 Hz
                frameSequencerCycles -= 8192
                clockFrameSequencer()
            }

            pulse1.advance(cycles: cycles)
            pulse2.advance(cycles: cycles)
            wave.advance(cycles: cycles)
            noise.advance(cycles: cycles)
        }

        // The channels change far more often than the 48,000 times per second the host plays
        // back, so each output sample is the average of everything since the previous one.
        let (left, right) = mix()
        accumulatedLeft += left * Float(cycles)
        accumulatedRight += right * Float(cycles)
        accumulatedCycles += cycles

        sampleClock += cycles * GameBoyAPU.sampleRate
        if sampleClock >= Int(GameBoyClock.frequency) {
            sampleClock -= Int(GameBoyClock.frequency)

            let inputLeft = accumulatedLeft / Float(accumulatedCycles)
            let inputRight = accumulatedRight / Float(accumulatedCycles)
            accumulatedLeft = 0
            accumulatedRight = 0
            accumulatedCycles = 0

            // High-pass filter: centers the signal around 0 so it doesn't pop
            let outputLeft = inputLeft - capacitorLeft
            let outputRight = inputRight - capacitorRight
            capacitorLeft = inputLeft - outputLeft * 0.996
            capacitorRight = inputRight - outputRight * 0.996

            pendingSamples.append(outputLeft)
            pendingSamples.append(outputRight)
        }
    }

    private func clockFrameSequencer() {
        if frameSequencerStep % 2 == 0 {
            pulse1.clockLength()
            pulse2.clockLength()
            wave.clockLength()
            noise.clockLength()
        }
        if frameSequencerStep == 2 || frameSequencerStep == 6 {
            pulse1.clockSweep()
        }
        if frameSequencerStep == 7 {
            pulse1.envelope.clock()
            pulse2.envelope.clock()
            noise.envelope.clock()
        }
        frameSequencerStep = (frameSequencerStep + 1) & 7
    }

    private var waveOutput: Int {
        guard wave.isEnabled else { return 0 }
        let byte = registers[0x20 + wave.position / 2] // Two samples per byte, upper half first
        let sample = wave.position % 2 == 0 ? byte >> 4 : byte & 0x0F
        return Int(sample) >> [4, 0, 1, 2][wave.volumeCode]
    }

    /// Combines the four channels into a left and a right value between 0 and 1.
    private func mix() -> (left: Float, right: Float) {
        let panning = registers[0x15] // NR51: bits 4-7 send channels 1-4 left, bits 0-3 send them right
        var left = 0
        var right = 0

        func add(_ output: Int, channel: Int) {
            if panning & (0x10 << channel) != 0 { left += output }
            if panning & (0x01 << channel) != 0 { right += output }
        }
        add(pulse1.output, channel: 0)
        add(pulse2.output, channel: 1)
        add(waveOutput, channel: 2)
        add(noise.output, channel: 3)

        // NR50: master volume, 0-7 per side (0 is quiet, not silent)
        let masterVolume = registers[0x14]
        let leftVolume = Float((masterVolume >> 4) & 0x07) + 1
        let rightVolume = Float(masterVolume & 0x07) + 1

        // 4 channels of up to 15 each, times a volume of up to 8
        return (Float(left) * leftVolume / 480, Float(right) * rightVolume / 480)
    }
}

/// A channel with a length counter: a countdown, ticking at 256 Hz, that switches the channel
/// off when it reaches zero. It is what makes a note stop without the game doing anything.
private protocol LengthCounted {
    var isEnabled: Bool { get set }
    var length: Int { get set }
    var isLengthEnabled: Bool { get set }
}

extension LengthCounted {
    mutating func clockLength() {
        if isLengthEnabled && length > 0 {
            length -= 1
            if length == 0 {
                isEnabled = false
            }
        }
    }
}
