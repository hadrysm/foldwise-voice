// Shared harness for driving full dictation sessions through the Pipeline
// seams (ADR-0002): protocol fakes for the record/transcribe stages, plus a
// state collector guarded by a lock because onState may fire off the main
// thread. The polish/insert stages are plain closures passed per-test.

import Foundation
import XCTest
@testable import FoldWiseVoiceKit

final class FakeRecorder: AudioRecording {
    var onFailure: ((AudioCaptureError) -> Void)?
    var samples: [Float]
    var startError: AudioCaptureError?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var closeCount = 0

    init(samples: [Float] = FakeRecorder.speech()) {
        self.samples = samples
    }

    func start() throws {
        if let startError { throw startError }
        startCount += 1
    }

    func stop() -> [Float] {
        stopCount += 1
        return samples
    }

    func close() {
        closeCount += 1
    }

    func fail(_ error: AudioCaptureError) {
        onFailure?(error)
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
    var onDownloadProgress: ((Double) -> Void)?
    var result: Result<String, Error> = .success("")
    /// Thrown by `prepare()` when set, so a test can drive a failed download.
    var prepareError: Error?
    /// Awaited at the start of every `transcribe` call, so a test can hold a
    /// session mid-transcription or fire `onLoading` while a job is active.
    var onTranscribe: (() async -> Void)?
    private(set) var warmupCount = 0
    private(set) var prepareCount = 0
    private(set) var received: [[Float]] = []

    func warmup() {
        warmupCount += 1
    }

    func prepare() async throws {
        prepareCount += 1
        if let prepareError { throw prepareError }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        received.append(samples)
        await onTranscribe?()
        return try result.get()
    }
}

final class FakeAudioDucker: AudioDucking {
    private(set) var events: [AudioDuckingEvent] = []

    func duck() {
        events.append(.duck)
    }

    func restore() {
        events.append(.restore)
    }
}

enum AudioDuckingEvent: Equatable {
    case duck
    case restore
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

final class ModeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Mode?

    var value: Mode? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
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
    ),
    pauseAudio: Bool = false
) -> Config {
    let fixture = mode.configFixture
    return Config(
        preferences: Config.Preferences(
            selection: fixture.selection,
            hotkey: "alt_r",
            toggleHotkey: nil,
            pauseAudio: pauseAudio,
            inputDevice: nil,
            asrModel: fixture.asrModel,
            appearance: .system,
            saveHistory: true,
            historyRetention: .default,
            sidebarCollapsed: false
        ),
        badgePosition: nil,
        orderedModes: fixture.orderedModes,
        path: FileManager.default.temporaryDirectory
            .appendingPathComponent("foldwise-pipeline-tests-\(UUID().uuidString)")
            .appendingPathComponent("config.json")
    )
}

private struct ModeConfigFixture {
    let selection: DictationSelection
    let asrModel: String
    let orderedModes: [Mode]
}

private extension Mode {
    var configFixture: ModeConfigFixture {
        let fixtureASRModel = asrModel.isEmpty ? ASRModelCatalog.defaultID : asrModel
        guard let llmModel, !llmModel.isEmpty else {
            return ModeConfigFixture(
                selection: .voiceToText,
                asrModel: fixtureASRModel,
                orderedModes: []
            )
        }
        let id = id ?? .random()
        return ModeConfigFixture(
            selection: .mode(id),
            asrModel: fixtureASRModel,
            orderedModes: [Mode(
                id: id,
                name: name,
                icon: icon,
                asrModel: fixtureASRModel,
                llmModel: llmModel,
                transformation: transformation,
                systemPrompt: systemPrompt ?? "Polish this transcript.",
                vocabulary: vocab
            )]
        )
    }
}

func preparePersistence(for config: Config, in testCase: XCTestCase) throws {
    let directory = config.path.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    testCase.addTeardownBlock {
        try FileManager.default.removeItem(at: directory)
    }
}
