// Microphone capture: 16 kHz mono Float32 (what Parakeet expects).
//
// The AVAudioEngine stays running for the app's lifetime once first used;
// frames are only buffered between start() and stop(). The input tap runs on
// a CoreAudio thread and must never block — it converts and appends under a
// lock, nothing more.

import AVFoundation
import Foundation

final class AudioRecorder {
    static let sampleRate = 16000.0

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var engineStarted = false

    private let lock = NSLock()
    private var buffered: [Float] = []
    private var recording = false
    private var _level: Float = 0

    /// Peak of the latest frame, for UI metering.
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
            NSLog("No audio input device available")
            return
        }
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
            channels: 1, interleaved: false
        )!
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer, outputFormat: outputFormat)
        }
        do {
            try engine.start()
            engineStarted = true
        } catch {
            NSLog("Audio engine failed to start: \(error.localizedDescription)")
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
        var peak: Float = 0
        for i in 0 ..< frames {
            peak = max(peak, abs(channel[i]))
        }

        lock.lock()
        if recording {
            buffered.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            _level = peak
        }
        lock.unlock()
    }
}
