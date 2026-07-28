// One Dictation session's live recognition (ADR-0009): captured chunks in,
// Transcript snapshots out, and one authoritative raw transcript out at release.
//
// Recovery is why this is a type rather than a few lines inside Pipeline. A live
// attempt is single-use, so a broken one is never resumed: the session re-feeds
// the recorder's retained buffer through a fresh attempt of the same model, and
// only a second failure falls back to the confirmed prefix.

import Foundation

final class LiveTranscription: @unchecked Sendable {
    /// What the session may still do. Ordered: capture ends at hotkey release,
    /// and a session that has ended never adopts an attempt opened after it.
    private enum Phase {
        /// Accepting audio and publishing snapshots.
        case capturing
        /// Hotkey released: presentation is frozen while finalization runs.
        case locked
        /// Abandoned — shutdown, capture failure, or a completed session.
        case ended
    }

    private let asrSession: any ASRSessionHandle
    private let onSnapshot: (TranscriptSnapshot) -> Void
    private let chunks: AsyncStream<[Float]>
    private let intake: AsyncStream<[Float]>.Continuation
    /// Recursive because `cancel()` may reach here from a snapshot consumer that
    /// decided this session is over.
    private let lock = NSRecursiveLock()
    private var phase = Phase.capturing
    private var attempt: (any TranscriptStreaming)?
    private var pump: Task<Void, Never>?
    private var failure: Error?
    /// The last snapshot published. Read instead of the attempt's own state so a
    /// caller holding Pipeline's state lock never waits on the attempt's lock
    /// while an engine report is waiting on Pipeline's.
    private var published: TranscriptSnapshot = .empty

    init(
        asrSession: any ASRSessionHandle,
        onSnapshot: @escaping (TranscriptSnapshot) -> Void
    ) {
        self.asrSession = asrSession
        self.onSnapshot = onSnapshot
        let intake = AsyncStream.makeStream(of: [Float].self)
        chunks = intake.stream
        self.intake = intake.continuation
    }

    /// The frozen text presentation shows from hotkey release onward.
    var snapshot: TranscriptSnapshot {
        withLock { published }
    }

    /// Timing points the streaming latency gate measures (PRD #351).
    var timings: TranscriptStreamTimings? {
        withLock { attempt }?.timings
    }

    /// Opens the attempt and starts feeding it, without making the hotkey wait on
    /// a model that may still be warming: chunks accepted before the attempt is
    /// open are queued and appended in order once it is.
    func begin() {
        let chunks = chunks
        let task = Task { [weak self] in
            guard let opened = await self?.openAttempt() else { return }
            for await chunk in chunks {
                guard let self, await feed(chunk, to: opened) else { return }
            }
        }
        withLock { pump = task }
    }

    /// Accepts one captured chunk from the recorder's delivery queue.
    func accept(_ chunk: [Float]) {
        let accepts = withLock {
            if case .capturing = phase {
                true
            } else {
                false
            }
        }
        guard accepts else { return }
        intake.yield(chunk)
    }

    /// Hotkey release: no further audio belongs to this session, and the snapshot
    /// presentation freezes on the last live text while finalization completes.
    func endCapture() {
        withLock {
            guard case .capturing = phase else { return }
            phase = .locked
        }
        intake.finish()
    }

    /// This session's authoritative raw transcript, layered so a live failure
    /// costs fidelity only as a last resort: the live attempt's own final, then a
    /// fresh attempt over `samples`, then the confirmed prefix.
    func resolve(retained samples: [Float]) async throws -> String {
        endCapture()
        await withLock { pump }?.value
        if let text = await finalizeLiveAttempt() {
            return text
        }
        do {
            return try await refeed(samples)
        } catch {
            let confirmed = withLock { published.committed }
            guard !confirmed.isEmpty else { throw error }
            Log.pipeline.error("""
            Live transcription recovery failed; keeping the confirmed prefix: \
            \(String(describing: error), privacy: .public)
            """)
            return confirmed
        }
    }

    /// Abandons the session. Idempotent, and synchronous so releasing a Dictation
    /// session never waits on the engine it was driving.
    func cancel() {
        let abandoned = withLock { () -> (any TranscriptStreaming)? in
            phase = .ended
            let pump = self.pump
            self.pump = nil
            pump?.cancel()
            return attempt
        }
        intake.finish()
        abandoned?.cancel()
    }

    /// The live attempt's own final, or `nil` when this session must recover: an
    /// attempt that never opened, one that failed mid-capture, and one whose
    /// finalization threw are the same event to the caller — the live stream did
    /// not produce a transcript.
    private func finalizeLiveAttempt() async -> String? {
        let attempt = withLock { () -> (any TranscriptStreaming)? in
            guard failure == nil else { return nil }
            return self.attempt
        }
        guard let attempt else { return nil }
        do {
            return try await attempt.finish()
        } catch {
            record(error)
            Log.pipeline.error("""
            Live transcription finalization failed: \
            \(String(describing: error), privacy: .public)
            """)
            return nil
        }
    }

    /// A fresh attempt over the buffer the recorder retained. Its snapshots are
    /// not published: recovery re-recognizes audio the caption has already shown,
    /// and a fresh attempt starts from empty text, so publishing would rewind the
    /// locked presentation instead of adding to it.
    private func refeed(_ samples: [Float]) async throws -> String {
        try Task.checkCancellation()
        let recovery = try await asrSession.makeStream()
        do {
            try await recovery.append(samples)
            return try await recovery.finish()
        } catch {
            recovery.cancel()
            throw error
        }
    }

    private func openAttempt() async -> (any TranscriptStreaming)? {
        let opened: any TranscriptStreaming
        do {
            opened = try await asrSession.makeStream()
        } catch {
            record(error)
            Log.pipeline.error("""
            Live transcription could not start: \
            \(String(describing: error), privacy: .public)
            """)
            return nil
        }
        // An attempt that opened after the session ended is abandoned rather than
        // adopted, so a shutdown mid-load leaves nothing driving the engine. One
        // that opened after hotkey release is still fed — the queued chunks are
        // this session's audio — but publishes nothing into a frozen caption.
        let adoption = withLock { () -> (adopted: Bool, publishes: Bool) in
            switch phase {
            case .capturing:
                attempt = opened
                return (true, true)
            case .locked:
                attempt = opened
                return (true, false)
            case .ended:
                return (false, false)
            }
        }
        guard adoption.adopted else {
            opened.cancel()
            return nil
        }
        if adoption.publishes {
            opened.deliverSnapshots { [weak self] snapshot in self?.publish(snapshot) }
        }
        return opened
    }

    /// Reports whether the pump may keep feeding this attempt. A failed append
    /// closes the attempt, so the queued chunks behind it are dropped rather than
    /// each failing again; the retained buffer is what recovery replays.
    private func feed(_ chunk: [Float], to attempt: any TranscriptStreaming) async -> Bool {
        do {
            try await attempt.append(chunk)
            return true
        } catch {
            record(error)
            Log.pipeline.error("""
            Live transcription lost its stream: \
            \(String(describing: error), privacy: .public)
            """)
            return false
        }
    }

    private func publish(_ snapshot: TranscriptSnapshot) {
        let consumer = withLock { () -> ((TranscriptSnapshot) -> Void)? in
            guard case .capturing = phase else { return nil }
            published = snapshot
            return onSnapshot
        }
        consumer?(snapshot)
    }

    private func record(_ error: Error) {
        withLock {
            guard failure == nil else { return }
            failure = error
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
