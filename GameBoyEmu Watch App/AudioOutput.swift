//
//  AudioOutput.swift
//  GameBoyEmu Watch App
//

/// The watch's stand-in for the phone app's `AudioOutput`: it plays nothing.
///
/// ponytail: no sound on the watch. The phone's version uses audio engine calls that are
/// deprecated on watchOS, and the watch's audio session needs different setting up. Write
/// a real one here when sound is wanted.
final class AudioOutput {
    init() throws {}

    func play(samples: [Float]) {}
}
