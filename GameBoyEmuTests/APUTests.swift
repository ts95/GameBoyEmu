import Foundation
import Testing
@testable import GameBoyEmu

/// Runs the APU for the given number of seconds of emulated time.
private func run(_ apu: GameBoyAPU, seconds: Double) {
    for _ in 0..<Int(seconds * GameBoyClock.frequency / 4) {
        apu.step(cycles: 4)
    }
}

@Test func pulseChannelPlaysASquareWaveAtTheRequestedPitch() throws {
    let apu = GameBoyAPU()
    apu[0xFF25] = 0x22 // Pulse 2 to both speakers
    apu[0xFF16] = 0x80 // 50% duty
    apu[0xFF17] = 0xF0 // Full volume, no fade
    apu[0xFF18] = 0xD6 // Frequency 1750: 131072 / (2048 - 1750) = 440 Hz
    apu[0xFF19] = 0x86 // Trigger

    #expect(apu[0xFF26] & 0x02 != 0) // NR52 reports pulse 2 as playing

    run(apu, seconds: 1)

    let left = stride(from: 0, to: apu.pendingSamples.count, by: 2).map { apu.pendingSamples[$0] }
    #expect(left.count == GameBoyAPU.sampleRate)

    let risingEdges = zip(left, left.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
    #expect((438...442).contains(risingEdges))
    #expect(left.max()! > 0.05)
}

@Test func lengthCounterSwitchesTheChannelOff() throws {
    let apu = GameBoyAPU()
    apu[0xFF17] = 0xF0
    apu[0xFF16] = 0x3C // Length 64 - 60 = 4 ticks of 1/256 s
    apu[0xFF19] = 0xC0 // Trigger with the length counter enabled

    run(apu, seconds: 0.01)
    #expect(apu[0xFF26] & 0x02 != 0)

    run(apu, seconds: 0.01)
    #expect(apu[0xFF26] & 0x02 == 0)
}

@Test func envelopeFadesANoteOut() throws {
    let apu = GameBoyAPU()
    apu[0xFF25] = 0x22
    apu[0xFF16] = 0x80
    apu[0xFF17] = 0xF1 // Start at full volume, one step down every 1/64 s
    apu[0xFF18] = 0xD6
    apu[0xFF19] = 0x86

    run(apu, seconds: 0.05)
    let loudness = apu.pendingSamples.map(abs).max()!
    apu.pendingSamples.removeAll()

    run(apu, seconds: 0.5) // 15 steps take 15/64 s, so the note has faded out by now
    apu.pendingSamples.removeAll()
    run(apu, seconds: 0.05)

    #expect(loudness > 0.05)
    #expect(apu.pendingSamples.map(abs).max()! < 0.001)
}

@Test func waveAndNoiseChannelsProduceSound() throws {
    let apu = GameBoyAPU()
    apu[0xFF25] = 0x44 // Wave channel only
    for address in 0xFF30...0xFF3F {
        apu[address] = address < 0xFF38 ? 0xFF : 0x00 // A square wave, as samples
    }
    apu[0xFF1A] = 0x80 // Wave channel on
    apu[0xFF1C] = 0x20 // 100% volume
    apu[0xFF1D] = 0xD6
    apu[0xFF1E] = 0x86
    run(apu, seconds: 0.05)
    #expect(apu.pendingSamples.map(abs).max()! > 0.05)

    apu.pendingSamples.removeAll()
    apu[0xFF25] = 0x88 // Noise channel only
    apu[0xFF21] = 0xF0
    apu[0xFF22] = 0x22
    apu[0xFF23] = 0x80
    run(apu, seconds: 0.05)
    #expect(apu.pendingSamples.map(abs).max()! > 0.05)
}

@Test func poweringTheAPUOffClearsItsRegisters() throws {
    let apu = GameBoyAPU()
    apu[0xFF17] = 0xF0
    apu[0xFF19] = 0x80
    apu[0xFF26] = 0x00 // Power off

    #expect(apu[0xFF26] == 0x70)
    #expect(apu[0xFF17] == 0x00)

    apu[0xFF17] = 0xF0 // Ignored while the power is off
    #expect(apu[0xFF17] == 0x00)
}
