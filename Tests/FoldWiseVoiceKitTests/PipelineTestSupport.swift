// Shared harness for driving full dictation sessions through the Pipeline
// seams (ADR-0002): protocol fakes for the record/transcribe stages, plus a
// state collector guarded by a lock because onState may fire off the main
// thread. The polish/insert stages are plain closures passed per-test.

import Foundation
@testable import FoldWiseVoiceKit

final class FakeRecorder: AudioRecording {
    var samples: [Float]
    private(set) var startCount = 0
    private(set) var closeCount = 0

    init(samples: [Float] = FakeRecorder.speech()) {
        self.samples = samples
    }

    func start() {
        startCount += 1
    }

    func stop() -> [Float] {
        samples
    }

    func close() {
        closeCount += 1
    }

    /// Canned capture loud enough and long enough to pass the Pipeline's
    /// minimum-length and near-silence gates.
    static func speech(seconds: Double = 1.0, amplitude: Float = 0.1) -> [Float] {
        [Float](repeating: amplitude, count: Int(AudioRecorder.sampleRate * seconds))
    }
}

final class FakeTranscriber: Transcribing {
    var ready = true
    var onLoading: ((Bool) -> Void)?
    var result: Result<String, Error> = .success("")
    private(set) var warmupCount = 0
    private(set) var received: [[Float]] = []

    func warmup() {
        warmupCount += 1
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        received.append(samples)
        return try result.get()
    }
}

final class StateCollector {
    private let lock = NSLock()
    private var collected: [PipelineState] = []

    func append(_ state: PipelineState) {
        lock.lock()
        collected.append(state)
        lock.unlock()
    }

    var states: [PipelineState] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}

/// A single-mode Config that never touches the filesystem (nothing saves it)
/// and keeps the audio ducker inert (`pauseAudio: false`).
func makeTestConfig(
    mode: Mode = Mode(
        name: "Voice to Text", asrModel: "", llmModel: nil, systemPrompt: nil, vocab: []
    )
) -> Config {
    Config(
        activeMode: mode.name, hotkey: "alt_r", toggleHotkey: nil, pauseAudio: false,
        hudPosition: nil, modeOrder: [mode.name], modes: [mode.name: mode],
        path: FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-pipeline-tests-\(UUID().uuidString).json")
    )
}
