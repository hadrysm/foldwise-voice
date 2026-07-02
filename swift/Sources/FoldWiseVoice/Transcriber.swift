// Stage 1: speech-to-text with Parakeet TDT v3 (FluidAudio) on the Neural
// Engine. Models auto-download from Hugging Face on first use (~600 MB),
// then everything is offline. warmup() preloads at launch so the first
// dictation is instant.

import FluidAudio
import Foundation

final class Transcriber {
    private var manager: AsrManager?
    private var loadTask: Task<AsrManager, Error>?
    /// True once models are loaded and transcription is instant.
    private(set) var ready = false

    /// Fired when a (down)load starts/ends, for HUD feedback.
    var onLoading: ((Bool) -> Void)?

    func warmup() {
        _ = ensureLoaded()
    }

    private func ensureLoaded() -> Task<AsrManager, Error> {
        if let loadTask { return loadTask }
        let task = Task<AsrManager, Error> { [weak self] in
            self?.onLoading?(true)
            defer { self?.onLoading?(false) }
            let models = try await AsrModels.downloadAndLoad()
            let manager = AsrManager()
            try await manager.loadModels(models)
            self?.ready = true
            return manager
        }
        loadTask = task
        return task
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let manager: AsrManager
        do {
            manager = try await ensureLoaded().value
        } catch {
            loadTask = nil  // allow a retry on the next dictation
            throw error
        }
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
