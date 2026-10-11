//
//  AudioOutput.swift
//  GameBoyEmu
//

import AVFoundation
import os

/// Plays the samples produced by the APU through the host's speakers.
///
/// The emulator hands over one frame's worth of samples (about 800) sixty times per second,
/// and the player node plays the queued buffers back to back.
///
/// Not thread-safe by itself: it belongs to the `Emulator` actor, which is also what keeps
/// the (blocking) audio session activation off the main thread.
final class AudioOutput {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(GameBoyAPU.sampleRate), channels: 2)!

    /// How many buffers are waiting to be played. The player reports a finished buffer on
    /// an audio thread, so this one piece of state is shared and sits behind a lock.
    private let queuedBuffers = OSAllocatedUnfairLock(initialState: 0)

    /// - Throws: If the host's audio hardware can't be started.
    init() throws {
        #if os(iOS) || os(tvOS)
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // The mixed signal is loud at full scale. The device's
        // own volume controls still apply on top.
        player.volume = 0.1

        try engine.start()
        player.play()
    }

    deinit {
        // Letting go of the output switches the sound hardware off, rather than leaving
        // an engine running with nothing to play
        player.stop()
        engine.stop()
    }

    /// Queues samples for playback.
    ///
    /// - Parameter samples: Interleaved left/right samples between -1 and 1.
    func play(samples: [Float]) {
        guard engine.isRunning, !samples.isEmpty else {
            return
        }

        // ponytail: the emulator and the sound card run off different clocks, so the queue is
        // kept between "about to run dry" and "falling behind" by padding and dropping whole
        // buffers. That can click now and then; pace emulation off the audio clock (or
        // resample) if it becomes noticeable.
        let queued = queuedBuffers.withLock { $0 }
        if queued == 0 {
            // Start (or restart after a stall) with 50 ms of silence, so that a frame arriving
            // a little late doesn't leave the speakers with nothing to play
            schedule(samples: [Float](repeating: 0, count: GameBoyAPU.sampleRate / 20 * 2))
        }
        guard queued < 8 else {
            return // More than ~130 ms behind: skip this frame's audio to catch up
        }
        schedule(samples: samples)
    }

    private func schedule(samples: [Float]) {
        let frameCount = samples.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for frame in 0..<frameCount {
            channels[0][frame] = samples[frame * 2]
            channels[1][frame] = samples[frame * 2 + 1]
        }

        queuedBuffers.withLock { $0 += 1 }
        player.scheduleBuffer(buffer) { [queuedBuffers] in
            queuedBuffers.withLock { $0 -= 1 }
        }
    }
}
