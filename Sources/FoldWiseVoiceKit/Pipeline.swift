// Wires the stages: record → Parakeet ASR → (optional Ollama polish) →
// paste. start/stop are called from the hotkey listener and must be fast;
// transcription jobs run in chained Tasks so they process in order without
// ever blocking the UI.

import Foundation
import os

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
    let recorder = AudioRecorder()
    let ducker = AudioDucker()
    let transcriber = Transcriber()

    /// May fire from any thread — UIs must hop to the main thread themselves.
    var onState: ((PipelineState) -> Void)?

    private var lastJob: Task<Void, Never>?
    private var jobActive = false
    private var lastEmitted: PipelineState = .idle

    init(config: Config) {
        self.config = config
        transcriber.onLoading = { [weak self] loading in
            guard let self else { return }
            if loading {
                guard !recorder.isRecording else { return }
                emit(.loadingModel)
            } else if lastEmitted == .loadingModel {
                // Back to whatever the load interrupted: a queued dictation
                // continues transcribing; a launch warmup returns to idle.
                emit(jobActive ? .transcribing : .idle)
            }
        }
    }

    private func emit(_ state: PipelineState) {
        lastEmitted = state
        onState?(state)
    }

    // MARK: - called from the hotkey listener (must be fast)

    func startRecording() {
        guard !recorder.isRecording else { return }
        if config.pauseAudio { ducker.duck() }
        recorder.start()
        emit(.listening(mode: config.activeMode))
    }

    func stopRecording() {
        guard recorder.isRecording else { return }
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
        if recorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
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
            text = await OllamaClient.polish(
                text, model: model, systemPrompt: mode.systemPrompt, vocab: mode.vocab
            )
            Log.pipeline.info("llm: \(text, privacy: .private)")
        }

        let finalText = text
        let pasted = await MainActor.run { TextInserter.insert(finalText) }
        emit(pasted ? .inserted : .clipboard)
    }
}
