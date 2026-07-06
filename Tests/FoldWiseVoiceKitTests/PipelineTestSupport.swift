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
    /// Awaited at the start of every `transcribe` call, so a test can hold a
    /// session mid-transcription or fire `onLoading` while a job is active.
    var onTranscribe: (() async -> Void)?
    private(set) var warmupCount = 0
    private(set) var received: [[Float]] = []

    func warmup() {
        warmupCount += 1
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        received.append(samples)
        await onTranscribe?()
        return try result.get()
    }
}

/// A one-shot async gate: `wait()` suspends until `open()`, which releases
/// every current and future waiter. Lets a test hold the first session in
/// its transcribe stage while it queues a second one behind it.
actor Latch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

/// Records each text handed to the insert stage, reporting `succeeds` back to
/// the Pipeline. Locked because the insert closure runs on a job Task.
final class InsertSpy {
    private let lock = NSLock()
    private var collected: [String] = []
    var succeeds = true

    func insert(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        collected.append(text)
        return succeeds
    }

    var texts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}

/// Records each `HistoryEntry` handed to the Pipeline's record seam. Locked
/// because the record closure runs on a job Task, off the main thread.
final class RecordSpy {
    private let lock = NSLock()
    private var collected: [HistoryEntry] = []

    func record(_ entry: HistoryEntry) {
        lock.lock()
        defer { lock.unlock() }
        collected.append(entry)
    }

    var entries: [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return collected
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
