// Microphone capture: 16 kHz mono Float32 (what Parakeet expects).
//
// The AVAudioEngine stays running for the app's lifetime once first used;
// frames are only buffered between start() and stop(). The input tap runs on
// a CoreAudio thread and must never block — it converts and appends under a
// lock, nothing more.

import AVFoundation
import Foundation
import os

final class AudioRecorder: AudioRecording {
    static let sampleRate = 16000.0

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var engineStarted = false

    private let lock = NSLock()
    private var buffered: [Float] = []
    private var recording = false
    private var _level: Float = 0

    /// RMS of the latest frame, feeding the Badge's ribbon amplitude through
    /// `LevelSmoother` (PRD #103).
    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return _level
    }

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recording
    }

    func open() {
        guard !engineStarted else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            Log.audio.error("No audio input device available")
            return
        }
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
            channels: 1, interleaved: false
        )!
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            Log.audio.error("Audio input format cannot be converted to 16 kHz mono")
            return
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer, outputFormat: outputFormat)
        }
        do {
            try engine.start()
            engineStarted = true
        } catch {
            Log.audio.error(
                "Audio engine failed to start: \(error.localizedDescription, privacy: .public)"
            )
            input.removeTap(onBus: 0)
        }
    }

    func close() {
        guard engineStarted else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engineStarted = false
    }

    func start() {
        open()
        lock.lock()
        buffered.removeAll(keepingCapacity: true)
        recording = true
        lock.unlock()
    }

    /// Stop buffering and return the captured audio.
    func stop() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        recording = false
        _level = 0
        let samples = buffered
        buffered = []
        return samples
    }

    private func consume(_ buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) {
        lock.lock()
        let active = recording
        lock.unlock()
        guard active, let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else { return }

        var served = false
        var error: NSError?
        // .noDataNow (not .endOfStream) keeps the converter primed across
        // taps so resampling stays continuous for the whole recording.
        converter.convert(to: out, error: &error) { _, status in
            if served {
                status.pointee = .noDataNow
                return nil
            }
            served = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0]
        else { return }

        let frames = Int(out.frameLength)
        var sumOfSquares: Float = 0
        for i in 0 ..< frames {
            sumOfSquares += channel[i] * channel[i]
        }
        let rms = frames > 0 ? sqrt(sumOfSquares / Float(frames)) : 0

        lock.lock()
        if recording {
            buffered.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            _level = rms
        }
        lock.unlock()
    }
}
