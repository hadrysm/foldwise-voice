// The second ASR engine (ADR-0005): Whisper via WhisperKit, in-process on the
// Neural Engine. Structural twin of `Transcriber` — it takes the recorder's
// `[Float]@16 kHz` buffer verbatim, auto-downloads its CoreML weights from
// Hugging Face on first load (~632 MB for large-v3-turbo), then runs offline.
// `variant` is the exact `argmaxinc/whisperkit-coreml` folder the catalog names.

import Foundation
import WhisperKit

final class WhisperTranscriber: Transcribing {
    /// WhisperKit isn't `Sendable` (unlike FluidAudio's `AsrManager`, which is
    /// why the twin Parakeet `Transcriber` needs no such box), so the loaded
    /// pipeline can't cross the load-`Task`'s concurrency boundary on its own.
    /// This wrapper asserts that safety by hand: the dictation pipeline drives
    /// one job at a time (`Pipeline` chains its jobs), so the pipe is only ever
    /// touched from a single serial context.
    private struct LoadedPipe: @unchecked Sendable {
        let pipe: WhisperKit
    }

    private let variant: String
    private var loadTask: Task<LoadedPipe, Error>?
    /// True once the model is loaded and transcription is instant.
    private(set) var ready = false

    /// Fired when a (down)load starts/ends, for Badge feedback.
    var onLoading: ((Bool) -> Void)?
    /// Fired with a 0…1 fraction while the CoreML weights download on first use,
    /// so the Badge and Speech pane can show a real percentage (#93).
    var onDownloadProgress: ((Double) -> Void)?

    init(variant: String) {
        self.variant = variant
    }

    func warmup() {
        _ = ensureLoaded()
    }

    func prepare() async throws {
        let task = ensureLoaded()
        do {
            // Propagate a caller's cancellation (the Speech pane's Cancel) into
            // the in-flight download/compile so it actually stops rather than
            // detaching and running on in the background.
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

    private func ensureLoaded() -> Task<LoadedPipe, Error> {
        if let loadTask { return loadTask }
        let variant = variant
        let task = Task<LoadedPipe, Error> { [weak self] in
            // Two phases so the Badge can distinguish them (#93): first fetch the
            // CoreML weights from Hugging Face, reporting a 0…1 fraction (a no-op
            // that resolves instantly once they're cached on disk)…
            let folder = try await WhisperKit.download(variant: variant) { [weak self] progress in
                self?.onDownloadProgress?(progress.fractionCompleted)
            }
            // …then compile and load them — the boolean spinner phase,
            // `modelFolder` set so this never re-downloads.
            //
            // Run the audio encoder on the GPU rather than WhisperKit's macOS-14
            // default of the Neural Engine: compiling the large-v3-turbo encoder
            // for the ANE on first load takes many minutes and often never
            // finishes, whereas the GPU path loads in well under a minute
            // (measured ~41s vs >6min unfinished on identical weights). The text
            // decoder stays on the ANE (WhisperKit's default), and GPU-encoder is
            // itself WhisperKit's own default on macOS < 14.
            self?.onLoading?(true)
            defer { self?.onLoading?(false) }
            let pipe = try await WhisperKit(
                WhisperKitConfig(
                    modelFolder: folder.path,
                    computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndGPU),
                    verbose: false, logLevel: .none, load: true
                )
            )
            self?.ready = true
            return LoadedPipe(pipe: pipe)
        }
        loadTask = task
        return task
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let loaded: LoadedPipe
        do {
            loaded = try await ensureLoaded().value
        } catch {
            loadTask = nil // allow a retry on the next dictation
            throw error
        }
        let results = try await loaded.pipe.transcribe(audioArray: samples)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
