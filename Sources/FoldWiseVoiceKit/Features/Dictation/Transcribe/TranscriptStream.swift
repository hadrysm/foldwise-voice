// One live recognition attempt over a loaded Streaming ASR model (ADR-0009):
// audio in, Transcript snapshots out, and a `finish()` result that *is* the
// transcript. An attempt is deliberately single-use — a failed one is recovered
// by re-feeding the recorder's retained buffer through a fresh attempt, so
// nothing here tries to resume a stream that has already closed.

import Foundation

/// Monotonic instants the streaming latency gate measures (PRD #351). Absolute
/// rather than pre-differenced, so the harness can relate them to its own
/// speech-onset origin.
struct TranscriptStreamTimings: Equatable {
    /// When the first captured sample reached the engine.
    var firstAppend: Duration?
    /// When the first non-empty snapshot became showable.
    var firstSnapshot: Duration?
    /// When finalization was requested — the hotkey-release origin.
    var finishRequested: Duration?
    /// When the authoritative final was ready.
    var finished: Duration?

    /// First visible feedback, relative to the first sample the engine saw.
    var timeToFirstSnapshot: Duration? {
        guard let firstAppend, let firstSnapshot else { return nil }
        return firstSnapshot - firstAppend
    }

    /// ASR's own post-release cost, which streaming is meant to keep flat.
    var finalization: Duration? {
        guard let finishRequested, let finished else { return nil }
        return finished - finishRequested
    }
}

enum TranscriptStreamError: LocalizedError {
    /// The Effective ASR model is not a Streaming ASR model.
    case streamingUnavailable
    /// A finished, abandoned, or released attempt cannot be reused.
    case streamClosed

    var errorDescription: String? {
        switch self {
        case .streamingUnavailable:
            "The selected speech model doesn't transcribe while you speak."
        case .streamClosed:
            "This dictation's live transcription has already ended."
        }
    }
}

/// A Streaming ASR model's engine-side driver, narrowed to what one live
/// Dictation session needs from the pinned FluidAudio streaming managers.
/// Injectable so attempt behavior is tested without loading real speech models.
protocol StreamingASRManaging: AnyObject {
    /// Loads model data. Called once per engine, before the first attempt.
    func load() async throws
    /// Subscribes the current attempt to the engine's absolute reports.
    /// `tentative` is revisable; `committed` marks an utterance boundary the
    /// engine declares final, and a manager without utterance detection never
    /// calls it.
    func observe(
        tentative: @escaping @Sendable (String) -> Void,
        committed: @escaping @Sendable (String) -> Void
    ) async
    func append(_ samples: [Float]) async throws
    func finish() async throws -> String
    /// Discards per-attempt state and leaves the model loaded, because exactly
    /// one ASR engine stays resident (ADR-0005).
    func reset() async
}

final class TranscriptStream: TranscriptStreaming, @unchecked Sendable {
    private enum Outcome {
        case open
        case finished(String)
        case abandoned
        case failed(Error)
    }

    /// What `finish()` has left to do once it has inspected the attempt's state.
    private enum Finalization {
        case drive(any StreamingASRManaging)
        case done(String)
    }

    /// Recursive, and snapshots are delivered while it is held, for the reason
    /// Pipeline's state lock is: a consumer may call straight back in, and the
    /// committed prefix would stop being append-only if two engine reports could
    /// interleave between being applied and being delivered.
    private let lock = NSRecursiveLock()
    private let monotonicNow: () -> Duration
    private var manager: (any StreamingASRManaging)?
    private var accumulator = TranscriptAccumulator()
    private var recorded = TranscriptStreamTimings()
    private var consumer: ((TranscriptSnapshot) -> Void)?
    private var outcome = Outcome.open

    private init(manager: any StreamingASRManaging, monotonicNow: @escaping () -> Duration) {
        self.manager = manager
        self.monotonicNow = monotonicNow
    }

    /// Binds `manager`'s reports to a fresh attempt. An async factory rather than
    /// an initializer because the managers are actors and must be subscribed
    /// before the caller appends its first sample.
    static func open(
        manager: any StreamingASRManaging,
        monotonicNow: @escaping () -> Duration
    ) async -> TranscriptStream {
        let stream = TranscriptStream(manager: manager, monotonicNow: monotonicNow)
        await manager.observe(
            tentative: { [weak stream] text in stream?.apply { $0.observeTentative(text) } },
            committed: { [weak stream] text in stream?.apply { $0.commit(text) } }
        )
        return stream
    }

    var snapshot: TranscriptSnapshot {
        withLock { accumulator.snapshot }
    }

    var timings: TranscriptStreamTimings {
        withLock { recorded }
    }

    func deliverSnapshots(to consumer: ((TranscriptSnapshot) -> Void)?) {
        withLock { self.consumer = consumer }
    }

    func append(_ samples: [Float]) async throws {
        let manager = try withLock { () -> (any StreamingASRManaging)? in
            let manager = try openManager()
            // A chunk with no frames is nothing to recognize, so it is neither an
            // engine call nor the instant the engine first saw audio.
            guard !samples.isEmpty else { return nil }
            if recorded.firstAppend == nil {
                recorded.firstAppend = monotonicNow()
            }
            return manager
        }
        guard let manager else { return }
        do {
            try await manager.append(samples)
        } catch {
            fail(with: error)
            throw error
        }
    }

    /// Idempotent: the transcript a healthy attempt settled on is answered again
    /// rather than recomputed, so a retried finalization cannot produce a second
    /// authority for one Dictation session.
    func finish() async throws -> String {
        let finalization: Finalization = try withLock {
            if case let .finished(text) = outcome {
                return .done(text)
            }
            let manager = try openManager()
            recorded.finishRequested = monotonicNow()
            return .drive(manager)
        }
        switch finalization {
        case let .done(text):
            return text
        case let .drive(manager):
            return try await finalize(with: manager)
        }
    }

    func cancel() {
        close(as: .abandoned)
    }

    private func finalize(with manager: any StreamingASRManaging) async throws -> String {
        let text: String
        do {
            text = try await manager.finish()
        } catch {
            fail(with: error)
            throw error
        }
        withLock {
            // A cancellation may have raced this finalization; the engine already
            // produced the text, so it is still answered, but an attempt that is
            // no longer this session's does not publish over the next one.
            guard case .open = outcome else { return }
            recorded.finished = monotonicNow()
            publish(accumulator.finalize(text))
            close(as: .finished(text))
        }
        return text
    }

    /// Applies one engine report and delivers the resulting snapshot under the
    /// lock. A report from an attempt that has already closed is dropped: its
    /// manager is now driving the next attempt.
    private func apply(_ update: (inout TranscriptAccumulator) -> TranscriptSnapshot) {
        withLock {
            guard case .open = outcome else { return }
            publish(update(&accumulator))
        }
    }

    private func publish(_ snapshot: TranscriptSnapshot) {
        if !snapshot.isEmpty, recorded.firstSnapshot == nil {
            recorded.firstSnapshot = monotonicNow()
        }
        consumer?(snapshot)
    }

    /// The manager an open attempt may drive. A closed attempt reports why it
    /// closed, so every later call fails the same way instead of silently
    /// succeeding against a reset engine.
    private func openManager() throws -> any StreamingASRManaging {
        switch outcome {
        case .open:
            guard let manager else { throw TranscriptStreamError.streamClosed }
            return manager
        case .finished, .abandoned:
            throw TranscriptStreamError.streamClosed
        case let .failed(error):
            throw error
        }
    }

    private func fail(with error: Error) {
        close(as: .failed(error))
    }

    /// Ends the attempt at most once and drops the engine, so a closed attempt
    /// stops driving — and stops retaining — the model the lifecycle may be about
    /// to replace. Nothing is reset here: every attempt starts from an engine the
    /// `StreamingTranscriber` has just reset, so ending one is a pure state change
    /// and stays synchronous for the lifecycle's session release.
    ///
    /// The accumulated snapshot survives: its committed prefix is the text a
    /// twice-failed session falls back to.
    private func close(as outcome: Outcome) {
        withLock {
            guard case .open = self.outcome else { return }
            self.outcome = outcome
            consumer = nil
            manager = nil
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
