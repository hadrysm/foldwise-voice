// Stage 1: speech-to-text with Parakeet TDT v3 (FluidAudio) on the Neural
// Engine. Models auto-download from Hugging Face on first use (~600 MB),
// then everything is offline. warmup() preloads at launch so the first
// dictation is instant.

import FluidAudio
import Foundation

final class Transcriber: Transcribing {
    private let version: ASRModelCatalog.ParakeetVariant
    private var manager: AsrManager?
    private var loadTask: Task<AsrManager, Error>?
    /// True once models are loaded and transcription is instant.
    private(set) var ready = false

    /// v3 (multilingual) is the default so `Transcriber()` and the launch warmup
    /// keep loading the out-of-box model; the dispatcher passes v2 for the
    /// English-only catalog entry.
    init(version: ASRModelCatalog.ParakeetVariant = .v3) {
        self.version = version
    }

    /// Fired when a (down)load starts/ends, for HUD feedback.
    var onLoading: ((Bool) -> Void)?
    /// FluidAudio surfaces no download fraction, so Parakeet never fires this
    /// and its first-load degrades to the boolean `onLoading` spinner (#93).
    var onDownloadProgress: ((Double) -> Void)?

    func warmup() {
        _ = ensureLoaded()
    }

    func prepare() async throws {
        let task = ensureLoaded()
        do {
            // Propagate a caller's cancellation (the Speech pane's Cancel, for a
            // downloadable Parakeet variant) into the in-flight download/load so
            // it actually stops rather than running on in the background.
            _ = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            loadTask = nil // allow a retry on the next download attempt
            throw error
        }
    }

    private func ensureLoaded() -> Task<AsrManager, Error> {
        if let loadTask { return loadTask }
        let version = ASRModelStore.fluidAudioVersion(version)
        let task = Task<AsrManager, Error> { [weak self] in
            self?.onLoading?(true)
            defer { self?.onLoading?(false) }
            let models = try await AsrModels.downloadAndLoad(version: version)
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
            loadTask = nil // allow a retry on the next dictation
            throw error
        }
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
