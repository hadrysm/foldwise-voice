// The second ASR engine (ADR-0005): Whisper via WhisperKit, in-process on the
// Neural Engine. Structural twin of `Transcriber` — it takes the recorder's
// `[Float]@16 kHz` buffer verbatim, auto-downloads its CoreML weights from
// Hugging Face on first load (~632 MB for large-v3-turbo), then runs offline.
// `variant` is the exact `argmaxinc/whisperkit-coreml` folder the catalog names.

import Foundation
import WhisperKit

final class WhisperTranscriber: Transcribing {
    private let variant: String
    private var loadTask: Task<WhisperKit, Error>?
    /// True once the model is loaded and transcription is instant.
    private(set) var ready = false

    /// Fired when a (down)load starts/ends, for HUD feedback.
    var onLoading: ((Bool) -> Void)?

    init(variant: String) {
        self.variant = variant
    }

    func warmup() {
        _ = ensureLoaded()
    }

    func prepare() async throws {
        do {
            _ = try await ensureLoaded().value
        } catch {
            loadTask = nil // allow a retry on the next download attempt
            throw error
        }
    }

    private func ensureLoaded() -> Task<WhisperKit, Error> {
        if let loadTask { return loadTask }
        let variant = variant
        let task = Task<WhisperKit, Error> { [weak self] in
            self?.onLoading?(true)
            defer { self?.onLoading?(false) }
            // download+load in one step; the ANE is WhisperKit's compute default.
            let pipe = try await WhisperKit(
                WhisperKitConfig(model: variant, verbose: false, logLevel: .none, load: true)
            )
            self?.ready = true
            return pipe
        }
        loadTask = task
        return task
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let pipe: WhisperKit
        do {
            pipe = try await ensureLoaded().value
        } catch {
            loadTask = nil // allow a retry on the next dictation
            throw error
        }
        let results = try await pipe.transcribe(audioArray: samples)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
