// A Streaming ASR model's engine (ADR-0009). It loads its streaming manager
// once and hands out one live attempt at a time, because exactly one ASR engine
// stays resident and one driver owns it (ADR-0005).
//
// The streaming managers have no batch mode, so this engine's batch
// `transcribe` is not a second authority: it is the PRD's re-feed path, a fresh
// attempt over a buffer the recorder retained.

import Foundation

actor StreamingTranscriber: StreamCapableTranscribing {
    typealias MakeManager = @Sendable () -> any StreamingASRManaging

    private let makeManager: MakeManager
    private let monotonicNow: () -> Duration
    private var loadTask: Task<any StreamingASRManaging, Error>?
    private weak var attempt: TranscriptStream?

    init(
        makeManager: @escaping MakeManager,
        monotonicNow: @escaping () -> Duration = Pipeline.continuousNow
    ) {
        self.makeManager = makeManager
        self.monotonicNow = monotonicNow
    }

    func prepare() async throws {
        let task = ensureLoaded()
        do {
            // Propagate lifecycle transaction cancellation into the in-flight
            // model load so it stops rather than running in the background.
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

    func makeStream() async throws -> any TranscriptStreaming {
        let manager = try await loadedManager()
        // One driver per loaded engine: an attempt still open when the next one
        // starts is abandoned rather than run beside it. Resetting here — rather
        // than when an attempt ends — is what lets an attempt end synchronously
        // and still guarantee every attempt starts from a clean engine.
        attempt?.cancel()
        await manager.reset()
        let stream = await TranscriptStream.open(manager: manager, monotonicNow: monotonicNow)
        attempt = stream
        return stream
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let stream = try await makeStream()
        do {
            try await stream.append(samples)
            return try await stream.finish()
        } catch {
            stream.cancel()
            throw error
        }
    }

    private func loadedManager() async throws -> any StreamingASRManaging {
        do {
            return try await ensureLoaded().value
        } catch {
            loadTask = nil // allow a retry on the next dictation
            throw error
        }
    }

    private func ensureLoaded() -> Task<any StreamingASRManaging, Error> {
        if let loadTask {
            return loadTask
        }
        let makeManager = makeManager
        let task = Task<any StreamingASRManaging, Error> {
            let manager = makeManager()
            try await manager.load()
            return manager
        }
        loadTask = task
        return task
    }
}
