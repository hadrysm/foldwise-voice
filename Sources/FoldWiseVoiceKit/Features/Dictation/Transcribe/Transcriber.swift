// Stage 1: speech-to-text with Parakeet TDT (FluidAudio) on the Neural Engine.
// Its family adapter owns storage availability and downloads; the ASR lifecycle
// constructs and prepares this resident engine only when activating a model.

import FluidAudio
import Foundation

final class Transcriber: Transcribing {
    private let version: ASRModelCatalog.ParakeetVariant
    private var loadTask: Task<AsrManager, Error>?

    /// v3 (multilingual) is the default out-of-box model; the Parakeet adapter
    /// passes v2 for the English-only catalog entry.
    init(version: ASRModelCatalog.ParakeetVariant = .v3) {
        self.version = version
    }

    func prepare() async throws {
        let task = ensureLoaded()
        do {
            // Propagate lifecycle transaction cancellation into the in-flight
            // engine load so it stops rather than running in the background.
            _ = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            loadTask = nil // allow a retry on the next activation attempt
            throw error
        }
    }

    private func ensureLoaded() -> Task<AsrManager, Error> {
        if let loadTask { return loadTask }
        let version = ASRModelStore.fluidAudioVersion(version)
        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(version: version)
            let manager = AsrManager()
            try await manager.loadModels(models)
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
