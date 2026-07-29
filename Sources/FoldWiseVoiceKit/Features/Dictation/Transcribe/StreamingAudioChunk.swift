// The FluidAudio streaming managers take `AVAudioPCMBuffer`, while the record
// seam delivers plain 16 kHz mono frames (ADR-0009). This wraps one chunk in the
// buffer they expect, declaring the format the recorder already produces so
// their internal converter has nothing to resample.

import AVFoundation
import Foundation

enum StreamingAudioChunk {
    /// One failure rather than one per step: from the caller's side an empty
    /// chunk and a buffer CoreAudio refused to allocate are the same event —
    /// this chunk cannot reach the engine.
    enum Failure: LocalizedError {
        case unusableChunk

        var errorDescription: String? {
            "Couldn't prepare the captured audio for transcription."
        }
    }

    static func buffer(for samples: [Float]) throws -> AVAudioPCMBuffer {
        guard !samples.isEmpty, let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioRecorder.sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0] else {
            throw Failure.unusableChunk
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }
}
