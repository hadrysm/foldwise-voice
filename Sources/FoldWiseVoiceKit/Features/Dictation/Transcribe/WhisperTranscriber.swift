// The second ASR engine (ADR-0005): Whisper via WhisperKit, in-process on the
// Neural Engine. Structural twin of `Transcriber` — it takes the recorder's
// `[Float]@16 kHz` buffer verbatim, auto-downloads its CoreML weights from
// Hugging Face on first load (~632 MB for large-v3-turbo), then runs offline.
// `variant` is the exact `argmaxinc/whisperkit-coreml` folder the catalog names.

import Foundation
import WhisperKit

enum SharedTaskValue {
    enum WaitError: Error {
        case waiterCancelled
    }

    private final class Waiter<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Error>?
        private var cancelled = false

        func registerIfActive(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
            let wasCancelled = lock.withLock {
                guard !cancelled else { return true }
                self.continuation = continuation
                return false
            }
            if wasCancelled {
                continuation.resume(throwing: WaitError.waiterCancelled)
                return false
            }
            return true
        }

        func cancel() {
            let continuation = lock.withLock {
                cancelled = true
                return takeContinuation()
            }
            continuation?.resume(throwing: WaitError.waiterCancelled)
        }

        func resolve(_ result: Result<Value, Error>) {
            let continuation = lock.withLock { takeContinuation() }
            continuation?.resume(with: result)
        }

        private func takeContinuation() -> CheckedContinuation<Value, Error>? {
            defer { continuation = nil }
            return continuation
        }
    }

    static func wait<Value: Sendable>(
        for task: Task<Value, Error>,
        onWaiterRegistered: @Sendable () -> Void = {}
    ) async throws -> Value {
        let waiter = Waiter<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if waiter.registerIfActive(continuation) { onWaiterRegistered() }
                Task { waiter.resolve(await task.result) }
            }
        } onCancel: {
            waiter.cancel()
        }
    }
}

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
    private let stateLock = NSLock()
    private var _loadTask: Task<LoadedPipe, Error>?
    /// True once the model is loaded and transcription is instant.
    private var _ready = false
    var ready: Bool {
        stateLock.withLock { _ready }
    }

    /// Fired when a (down)load starts/ends, for Badge feedback.
    private var _onLoading: ((Bool) -> Void)?
    var onLoading: ((Bool) -> Void)? {
        get { stateLock.withLock { _onLoading } }
        set { stateLock.withLock { _onLoading = newValue } }
    }

    /// Fired with a 0…1 fraction while the CoreML weights download on first use,
    /// so the Badge and Speech pane can show a real percentage (#93).
    private var _onDownloadProgress: ((Double) -> Void)?
    var onDownloadProgress: ((Double) -> Void)? {
        get { stateLock.withLock { _onDownloadProgress } }
        set { stateLock.withLock { _onDownloadProgress = newValue } }
    }

    init(variant: String) {
        self.variant = variant
    }

    func warmup() {
        _ = ensureLoaded()
    }

    func prepare() async throws {
        let task = ensureLoaded()
        do {
            // Cancel only this waiter. Warmup, transcription, or another
            // preparation may still depend on the shared download/compile.
            _ = try await SharedTaskValue.wait(for: task)
        } catch SharedTaskValue.WaitError.waiterCancelled {
            throw CancellationError()
        } catch {
            clearLoadTask(task) // allow a retry after a shared-load failure
            throw error
        }
    }

    private func ensureLoaded() -> Task<LoadedPipe, Error> {
        stateLock.withLock {
            if let loadTask = _loadTask { return loadTask }
            let variant = variant
            let task = Task<LoadedPipe, Error> { [weak self] in
                // Two phases so the Badge can distinguish them (#93): first fetch the
                // CoreML weights from Hugging Face, reporting a 0…1 fraction (a no-op
                // that resolves instantly once they're cached on disk)…
                let folder = try await WhisperKit.download(variant: variant) { [weak self] progress in
                    self?.notifyDownloadProgress(progress.fractionCompleted)
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
                self?.notifyLoading(true)
                defer { self?.notifyLoading(false) }
                let pipe = try await WhisperKit(
                    WhisperKitConfig(
                        modelFolder: folder.path,
                        computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndGPU),
                        verbose: false, logLevel: .none, load: true
                    )
                )
                self?.markReady()
                return LoadedPipe(pipe: pipe)
            }
            _loadTask = task
            return task
        }
    }

    private func clearLoadTask(_ task: Task<LoadedPipe, Error>) {
        stateLock.withLock {
            if _loadTask == task { _loadTask = nil }
        }
    }

    private func markReady() {
        stateLock.withLock { _ready = true }
    }

    private func notifyLoading(_ loading: Bool) {
        let callback = stateLock.withLock { _onLoading }
        callback?(loading)
    }

    private func notifyDownloadProgress(_ fraction: Double) {
        let callback = stateLock.withLock { _onDownloadProgress }
        callback?(fraction)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let task = ensureLoaded()
        let loaded: LoadedPipe
        do {
            loaded = try await SharedTaskValue.wait(for: task)
        } catch SharedTaskValue.WaitError.waiterCancelled {
            throw CancellationError()
        } catch {
            clearLoadTask(task) // allow a retry after a shared-load failure
            throw error
        }
        let results = try await loaded.pipe.transcribe(audioArray: samples)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
