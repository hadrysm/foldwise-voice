// Wires the stages: record → Parakeet ASR → (optional Ollama polish) →
// paste. start/stop are called from the hotkey listener and must be fast;
// transcription jobs run in chained Tasks so they process in order without
// ever blocking the UI.

import Foundation
import os

/// The record stage's seam (ADR-0002). `AudioRecorder` is the production
/// conformer; tests inject a fake with canned samples.
protocol AudioRecording: AnyObject {
    func start()
    func stop() -> [Float]
    func close()
}

/// The transcribe stage's seam (ADR-0002). Mirrors `Transcriber`'s full
/// surface because the asynchronous loading-model dance is part of the
/// behavior under test.
protocol Transcribing: AnyObject {
    var ready: Bool { get }
    var onLoading: ((Bool) -> Void)? { get set }
    func warmup()
    func transcribe(_ samples: [Float]) async throws -> String
}

enum PipelineState: Equatable {
    case listening(mode: String)
    case loadingModel
    case transcribing
    case polishing(model: String)
    case inserted
    case clipboard
    case idle
    case error(String)
}

final class Pipeline {
    let config: Config
    let ducker = AudioDucker()

    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let polish: (String, Mode) async -> String
    private let insert: (String) async -> Bool

    /// May fire from any thread — UIs must hop to the main thread themselves.
    var onState: ((PipelineState) -> Void)?

    /// Owned here rather than read back through the record seam, so the
    /// start/stop guards are self-contained and fakes needn't track it.
    private var recording = false
    private var lastJob: Task<Void, Never>?
    private var jobActive = false
    private var lastEmitted: PipelineState = .idle

    init(
        config: Config,
        recorder: AudioRecording = AudioRecorder(),
        transcriber: Transcribing = Transcriber(),
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish,
        insert: @escaping (String) async -> Bool = Pipeline.pasteboardInsert
    ) {
        self.config = config
        self.recorder = recorder
        self.transcriber = transcriber
        self.polish = polish
        self.insert = insert
        self.transcriber.onLoading = { [weak self] loading in
            guard let self else { return }
            if loading {
                guard !recording else { return }
                emit(.loadingModel)
            } else if lastEmitted == .loadingModel {
                // Back to whatever the load interrupted: a queued dictation
                // continues transcribing; a launch warmup returns to idle.
                emit(jobActive ? .transcribing : .idle)
            }
        }
    }

    // MARK: - production stage defaults

    static func ollamaPolish(_ text: String, mode: Mode) async -> String {
        guard let model = mode.llmModel else { return text }
        return await OllamaClient.polish(
            text, model: model, systemPrompt: mode.systemPrompt, vocab: mode.vocab
        )
    }

    static func pasteboardInsert(_ text: String) async -> Bool {
        await MainActor.run { TextInserter.insert(text) }
    }

    private func emit(_ state: PipelineState) {
        lastEmitted = state
        onState?(state)
    }

    // MARK: - called from the hotkey listener (must be fast)

    func startRecording() {
        guard !recording else { return }
        recording = true
        if config.pauseAudio { ducker.duck() }
        recorder.start()
        emit(.listening(mode: config.activeMode))
    }

    func stopRecording() {
        guard recording else { return }
        recording = false
        let samples = recorder.stop()
        ducker.restore()
        emit(.transcribing)
        let mode = config.mode
        let previous = lastJob
        lastJob = Task {
            await previous?.value
            await self.process(samples, mode: mode)
        }
    }

    func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Test hook: awaits the most recently queued session job. Each job
    /// awaits its predecessor, so this drains the whole chain.
    func awaitPendingJob() async {
        await lastJob?.value
    }

    func shutdown() {
        ducker.restore()
        recorder.close()
    }

    // MARK: - worker

    private func process(_ samples: [Float], mode: Mode) async {
        jobActive = true
        defer { jobActive = false }
        guard samples.count >= 1600 else { // < 0.1 s — no real audio captured
            emit(.idle)
            return
        }
        // Near-silence makes ASR hallucinate — skip it.
        guard samples.contains(where: { abs($0) >= 0.005 }) else {
            emit(.idle)
            return
        }

        var text: String
        do {
            if !transcriber.ready { emit(.loadingModel) }
            text = try await transcriber.transcribe(samples)
        } catch {
            Log.pipeline.error(
                "Transcription failed: \(String(describing: error), privacy: .public)"
            )
            emit(.error("\(error)"))
            return
        }
        guard !text.isEmpty else {
            emit(.idle)
            return
        }
        Log.pipeline.info("raw: \(text, privacy: .private)")

        if mode.usesLLM, let model = mode.llmModel, text.count > MIN_CHARS_FOR_LLM {
            emit(.polishing(model: model))
            text = await polish(text, mode)
            Log.pipeline.info("llm: \(text, privacy: .private)")
        }

        let pasted = await insert(text)
        emit(pasted ? .inserted : .clipboard)
    }
}
