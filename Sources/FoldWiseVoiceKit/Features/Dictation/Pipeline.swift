// Wires the stages: record → on-device ASR → (optional Ollama polish) →
// paste. start/stop are called from the hotkey listener and must be fast;
// transcription jobs run in chained Tasks so they process in order without
// ever blocking the UI.

import AppKit
import Foundation
import os

/// The record stage's seam (ADR-0002). `AudioRecorder` is the production
/// conformer; tests inject a fake with canned samples.
protocol AudioRecording: AnyObject {
    var onFailure: ((AudioCaptureError) -> Void)? { get set }
    func start() throws
    func stop() -> [Float]
    func close()
    /// Incremental delivery beside the retained final buffer (ADR-0009): a
    /// Streaming ASR model subscribes before `start()` and receives the
    /// session's 16 kHz mono chunks in order as they are captured. Passing
    /// `nil` detaches, including mid-session.
    func deliverSamples(to consumer: (([Float]) -> Void)?)
}

extension AudioRecording {
    /// Batch-only recorders keep `stop()` as their single authority, so they
    /// opt out of incremental delivery by not implementing it.
    func deliverSamples(to _: (([Float]) -> Void)?) {}
}

/// A Dictation session's captured transcription capability. Pipeline can use
/// and release it without learning which model or engine the lifecycle owns.
protocol ASRSessionHandle: AnyObject {
    /// Whether this session's Effective ASR model transcribes while the user
    /// speaks (ADR-0009). A yes/no question, never a model identity: capability
    /// comes from the engine's type, not from the catalog's presentation flag.
    var canStream: Bool { get }
    /// Opens one live recognition attempt. Throws when the model cannot stream,
    /// so a caller that skipped `canStream` fails loudly instead of silently
    /// transcribing nothing.
    func makeStream() async throws -> any TranscriptStreaming
    func transcribe(_ samples: [Float]) async throws -> String
    func release()
}

extension ASRSessionHandle {
    /// A batch model's session answers "no" without implementing anything, which
    /// is why streaming is a type refinement rather than a widened interface.
    var canStream: Bool {
        false
    }

    func makeStream() async throws -> any TranscriptStreaming {
        throw TranscriptStreamError.streamingUnavailable
    }
}

/// Captures the Effective ASR model when a Dictation session starts recording.
protocol ASRSessionHandleProviding: AnyObject {
    var isDictationBlocked: Bool { get }
    func captureSession() throws -> any ASRSessionHandle
}

/// The engine-family adapter seam (ADR-0002). Concrete engines stay behind a
/// lifecycle-owned `ASRSessionHandle` in production.
protocol Transcribing: AnyObject {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

/// A Streaming ASR model's engine (ADR-0009). `Transcribing` is *refined* rather
/// than widened, so batch engines need no streaming method and capability is a
/// fact the type system checks instead of a nil every adapter must remember.
protocol StreamCapableTranscribing: Transcribing {
    /// Opens one live recognition attempt. Streaming sessions serialize, so the
    /// engine drives at most one attempt at a time.
    func makeStream() async throws -> any TranscriptStreaming
}

/// One live recognition attempt. Its `finish()` result is the transcript that
/// Polish, History, and the single atomic insertion consume (ADR-0009).
protocol TranscriptStreaming: AnyObject {
    /// Subscribes the Transcript-snapshot consumer; `nil` detaches. Snapshots
    /// never arrive on the audio render thread.
    func deliverSnapshots(to consumer: ((TranscriptSnapshot) -> Void)?)
    /// The latest snapshot. Its committed prefix is the text a twice-failed
    /// session falls back to, and only as a last resort.
    var snapshot: TranscriptSnapshot { get }
    /// Timing points the streaming latency gate measures (PRD #351).
    var timings: TranscriptStreamTimings { get }
    func append(_ samples: [Float]) async throws
    func finish() async throws -> String
    /// Abandons the attempt and drops the engine it was driving. Idempotent, and
    /// synchronous so releasing a Dictation session never waits on it.
    func cancel()
}

enum PipelineState: Equatable {
    case listening(mode: String)
    /// A model's weights are downloading on first use; `fraction` is 0…1.
    case downloadingModel(fraction: Double)
    case loadingModel
    case switchingASRModel
    case transcribing
    case polishing(model: String)
    case recognitionUnavailable
    case inserted
    case clipboard
    case idle
    case error(String)
}

enum DictationSessionEvent: Equatable {
    case started(UUID)
    case finished(UUID)
}

/// One Dictation session's live recognition progress (ADR-0009). Carried on its
/// own observer rather than as a `PipelineState` case, so snapshots arriving at
/// the engine's cadence cannot disturb the ordered progress-state sequence, and
/// so a consumer can tell whose session it is watching.
struct DictationTranscript: Equatable {
    /// Whether later audio may still rewrite the snapshot.
    enum Phase: Equatable {
        /// The user is still speaking.
        case live
        /// The hotkey is released: the raw text is frozen while the session
        /// finalizes and, if the Mode asks for it, polishes.
        case locked
    }

    let dictationSessionID: UUID
    let snapshot: TranscriptSnapshot
    let phase: Phase
}

final class Pipeline {
    private struct RecordingContext {
        let dictationSessionID: UUID
        let mode: Mode
        let asrSession: any ASRSessionHandle
        /// Present only while a Streaming ASR model is effective *and* no earlier
        /// streaming session is still driving it.
        let live: LiveTranscription?
    }

    let config: Config

    private let recorder: AudioRecording
    private let sessionProvider: ASRSessionHandleProviding
    private let ducker: AudioDucking
    private let warmPolishModel: (Mode) -> Void
    private let polish: (String, Mode) async -> OllamaPolishResult
    private let insert: (String) async -> Bool
    /// Best-effort history sink (PRD #78): handed the assembled entry after
    /// insertion. A closure seam mirroring `polish`/`insert` (ADR-0002).
    private let record: (HistoryEntry) -> Void
    /// Frontmost-app name at insert time. Injectable so tests stay AppKit-free.
    private let frontmostApp: () async -> String?
    /// Monotonic time since an arbitrary origin. Production uses
    /// `ContinuousClock`; tests inject deterministic instants.
    private let monotonicNow: () -> Duration

    /// Recursive because state observers and injected effects may synchronously
    /// call back into the Pipeline. State delivery stays inside the lock so a
    /// callback accepted before shutdown cannot arrive after terminal idle.
    private let stateLock = NSRecursiveLock()

    /// May fire from any thread — UIs must hop to the main thread themselves.
    var onState: ((PipelineState) -> Void)?
    /// Paired identity events for lifecycle policy; unlike presentation states,
    /// an unmatched startup error cannot finish another queued session.
    var onSessionEvent: ((DictationSessionEvent) -> Void)?
    /// Live recognition progress, for sessions whose Effective ASR model streams.
    /// May fire from any thread, at the engine's cadence.
    var onTranscript: ((DictationTranscript) -> Void)?

    /// Owned here rather than read back through the record seam, so the
    /// start/stop guards are self-contained and fakes needn't track it.
    private var recording = false
    private var recordingStartID: UUID?
    private var recordingContext: RecordingContext?
    private var lastJob: Task<Void, Never>?
    private var jobActive = false
    /// Whether a streaming session still owns the loaded engine. One driver per
    /// loaded engine (ADR-0005), so a Dictation session that starts while this is
    /// `true` records without live snapshots and recovers by re-feed.
    private var liveTranscriptionInFlight = false
    private var lastEmitted: PipelineState = .idle
    private var isShutDown = false

    private static let continuousClock = ContinuousClock()
    private static let timingOrigin = continuousClock.now

    init(
        config: Config,
        recorder: AudioRecording,
        sessionProvider: ASRSessionHandleProviding,
        ducker: AudioDucking = AudioDucker(),
        warmPolishModel: @escaping (Mode) -> Void = { _ in },
        polish: @escaping (String, Mode) async -> OllamaPolishResult =
            Pipeline.ollamaPolishWithTiming,
        insert: @escaping (String) async -> Bool = Pipeline.pasteboardInsert,
        record: @escaping (HistoryEntry) -> Void = Pipeline.recordToHistory,
        frontmostApp: @escaping () async -> String? = Pipeline.frontmostAppName,
        monotonicNow: @escaping () -> Duration = Pipeline.continuousNow
    ) {
        self.config = config
        self.recorder = recorder
        self.sessionProvider = sessionProvider
        self.ducker = ducker
        self.warmPolishModel = warmPolishModel
        self.polish = polish
        self.insert = insert
        self.record = record
        self.frontmostApp = frontmostApp
        self.monotonicNow = monotonicNow
        self.recorder.onFailure = { [weak self] error in
            self?.recordingFailed(error)
        }
    }

    /// Compatibility initializer for tests and text-only callers that do not
    /// observe Ollama's native timing metadata.
    convenience init(
        config: Config,
        recorder: AudioRecording,
        sessionProvider: ASRSessionHandleProviding,
        ducker: AudioDucking = AudioDucker(),
        warmPolishModel: @escaping (Mode) -> Void = { _ in },
        polish: @escaping (String, Mode) async -> String,
        insert: @escaping (String) async -> Bool = Pipeline.pasteboardInsert,
        record: @escaping (HistoryEntry) -> Void = Pipeline.recordToHistory,
        frontmostApp: @escaping () async -> String? = Pipeline.frontmostAppName,
        monotonicNow: @escaping () -> Duration = Pipeline.continuousNow
    ) {
        self.init(
            config: config,
            recorder: recorder,
            sessionProvider: sessionProvider,
            ducker: ducker,
            warmPolishModel: warmPolishModel,
            polish: { text, mode in
                OllamaPolishResult(text: await polish(text, mode), timing: nil)
            },
            insert: insert,
            record: record,
            frontmostApp: frontmostApp,
            monotonicNow: monotonicNow
        )
    }

    // MARK: - production stage defaults

    static func ollamaPolish(_ text: String, mode: Mode) async -> String {
        await ollamaPolishWithTiming(text, mode: mode).text
    }

    static func ollamaPolishWithTiming(
        _ text: String,
        mode: Mode
    ) async -> OllamaPolishResult {
        guard let model = mode.llmModel else {
            return OllamaPolishResult(text: text, timing: nil)
        }
        return await OllamaClient().polishWithTiming(
            text, model: model, systemPrompt: mode.systemPrompt, vocab: mode.vocab,
            expands: mode.expands
        )
    }

    static func continuousNow() -> Duration {
        timingOrigin.duration(to: continuousClock.now)
    }

    static func pasteboardInsert(_ text: String) async -> Bool {
        await TextInserter.insert(text)
    }

    static func recordToHistory(_ entry: HistoryEntry) {
        JSONLHistoryStore(url: JSONLHistoryStore.defaultURL).append(entry)
    }

    static func frontmostAppName() async -> String? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName }
    }

    /// Delivers `state` unless shutdown is complete, then reports whether the
    /// Pipeline remained active after the observer returned.
    @discardableResult
    private func emit(_ state: PipelineState) -> Bool {
        withStateLock {
            guard !isShutDown else { return false }
            deliver(state)
            return !isShutDown
        }
    }

    private func deliver(_ state: PipelineState) {
        lastEmitted = state
        onState?(state)
    }

    private func withStateLock<T>(_ operation: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try operation()
    }

    // MARK: - called from the hotkey listener (must be fast)

    func startRecording() {
        let start: (id: UUID, mode: Mode)? = withStateLock {
            guard !isShutDown, !recording, !sessionProvider.isDictationBlocked else {
                return nil
            }
            let asrSession: any ASRSessionHandle
            do {
                asrSession = try sessionProvider.captureSession()
            } catch {
                Log.pipeline.error(
                    "ASR session capture skipped: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
            if config.pauseAudio {
                ducker.duck()
            }
            recording = true
            let mode = config.mode
            let id = UUID()
            recordingStartID = id
            recordingContext = RecordingContext(
                dictationSessionID: id,
                mode: mode,
                asrSession: asrSession,
                live: beginLiveTranscription(for: asrSession, dictationSessionID: id)
            )
            return (id, mode)
        }
        guard let start else { return }

        do {
            try recorder.start()
        } catch {
            withStateLock {
                guard recordingStartID == start.id else { return }
                recording = false
                recordingStartID = nil
                releaseRecordingContext()
                ducker.restore()
                emit(.error(error.localizedDescription))
            }
            return
        }
        let shouldStop = withStateLock {
            guard !isShutDown, recording, recordingStartID == start.id else { return true }
            recordingStartID = nil
            deliverSessionEvent(.started(start.id))
            emit(.listening(mode: start.mode.name))
            return false
        }
        if shouldStop {
            _ = recorder.stop()
            return
        }
        if start.mode.usesLLM {
            warmPolishModel(start.mode)
        }
    }

    func stopRecording() {
        let requestedAt = monotonicNow()
        withStateLock {
            guard !isShutDown, recording else { return }
            recording = false
            if recordingStartID != nil {
                recordingStartID = nil
                releaseRecordingContext()
                ducker.restore()
                return
            }
            let samples = recorder.stop()
            recorder.deliverSamples(to: nil)
            ducker.restore()
            guard let context = recordingContext else { return }
            recordingContext = nil
            let asrSession = context.asrSession
            // Hotkey release freezes the raw text: nothing recognized after this
            // instant rewrites what the user is looking at while it finalizes.
            if let live = context.live {
                live.endCapture()
                publish(live.snapshot, for: context.dictationSessionID, phase: .locked)
            }
            guard emit(.transcribing) else {
                asrSession.release()
                endLiveTranscription(context.live)
                deliverSessionEvent(.finished(context.dictationSessionID))
                return
            }
            // Unlike the start-time Mode snapshot, whether this session is saved is
            // decided when the user stops speaking, not read later off the job task.
            let saveHistory = config.saveHistory
            let previous = lastJob
            lastJob = Task {
                defer { self.finishDictationSession(context.dictationSessionID) }
                await withTaskCancellationHandler {
                    await previous?.value
                    guard !Task.isCancelled else {
                        asrSession.release()
                        self.endLiveTranscription(context.live)
                        return
                    }
                    await self.process(
                        samples,
                        context: context,
                        saveHistory: saveHistory,
                        requestedAt: requestedAt
                    )
                } onCancel: {
                    previous?.cancel()
                }
            }
        }
    }

    func toggleRecording() {
        let shouldStop = withStateLock { !isShutDown && recording }
        if shouldStop {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Test hook: awaits the most recently queued session job. Each job
    /// awaits its predecessor, so this drains the whole chain.
    func awaitPendingJob() async {
        let pendingJob = withStateLock { lastJob }
        await pendingJob?.value
    }

    func shutdown() {
        let shouldClose: Bool = withStateLock {
            guard !isShutDown else { return false }
            isShutDown = true
            let activeRecordingSessionID = recordingStartID == nil
                ? recordingContext?.dictationSessionID
                : nil
            recording = false
            recordingStartID = nil
            releaseRecordingContext()
            lastJob?.cancel()
            ducker.restore()
            deliver(.idle)
            if let activeRecordingSessionID {
                deliverSessionEvent(.finished(activeRecordingSessionID))
            }
            return true
        }
        if shouldClose {
            recorder.close()
        }
    }

    private func recordingFailed(_ error: AudioCaptureError) {
        withStateLock {
            guard !isShutDown, recording else { return }
            let activeRecordingSessionID = recordingStartID == nil
                ? recordingContext?.dictationSessionID
                : nil
            recording = false
            recordingStartID = nil
            releaseRecordingContext()
            ducker.restore()
            emit(.error(error.localizedDescription))
            if let activeRecordingSessionID {
                deliverSessionEvent(.finished(activeRecordingSessionID))
            }
        }
    }

    private func releaseRecordingContext() {
        recordingContext?.asrSession.release()
        endLiveTranscription(recordingContext?.live)
        recordingContext = nil
    }

    // MARK: - live recognition

    /// Opens this session's live attempt when its Effective ASR model streams and
    /// no earlier streaming session is still driving that engine. Subscribing to
    /// the recorder happens here, before capture starts, because a session
    /// captures its incremental delivery exactly as it captures its ASR model.
    private func beginLiveTranscription(
        for asrSession: any ASRSessionHandle,
        dictationSessionID id: UUID
    ) -> LiveTranscription? {
        recorder.deliverSamples(to: nil)
        guard asrSession.canStream, !liveTranscriptionInFlight else { return nil }
        liveTranscriptionInFlight = true
        let live = LiveTranscription(asrSession: asrSession) { [weak self] snapshot in
            self?.publish(snapshot, for: id, phase: .live)
        }
        recorder.deliverSamples(to: { [weak live] chunk in live?.accept(chunk) })
        live.begin()
        return live
    }

    /// Ends a session's live attempt and frees the engine's driver slot. Safe on
    /// every completion path: abandoning an attempt that already finalized is a
    /// no-op, so the slot is released exactly once whether the session inserted,
    /// failed, or was shut down.
    private func endLiveTranscription(_ live: LiveTranscription?) {
        guard let live else { return }
        live.cancel()
        withStateLock { liveTranscriptionInFlight = false }
    }

    private func publish(
        _ snapshot: TranscriptSnapshot,
        for dictationSessionID: UUID,
        phase: DictationTranscript.Phase
    ) {
        withStateLock {
            guard !isShutDown else { return }
            onTranscript?(DictationTranscript(
                dictationSessionID: dictationSessionID,
                snapshot: snapshot,
                phase: phase
            ))
        }
    }

    private func finishDictationSession(_ id: UUID) {
        withStateLock {
            deliverSessionEvent(.finished(id))
        }
    }

    private func deliverSessionEvent(_ event: DictationSessionEvent) {
        onSessionEvent?(event)
    }

    // MARK: - worker

    private func process(
        _ samples: [Float],
        context: RecordingContext,
        saveHistory: Bool,
        requestedAt: Duration
    ) async {
        let mode = context.mode
        let asrSession = context.asrSession
        let processingStartedAt = monotonicNow()
        let started = withStateLock {
            guard !isShutDown else { return false }
            jobActive = true
            return true
        }
        guard started else {
            asrSession.release()
            endLiveTranscription(context.live)
            return
        }
        defer { withStateLock { jobActive = false } }
        let transcribeStartedAt = monotonicNow()
        guard var text = await transcribe(samples, using: asrSession, live: context.live) else {
            return
        }
        let transcribeFinishedAt = monotonicNow()
        guard !text.isEmpty else {
            emit(.idle)
            return
        }
        Log.pipeline.info("raw: \(text, privacy: .private)")
        let rawText = text
        // The authoritative raw transcript replaces whatever the live attempt had
        // shown, so the frozen caption agrees with what Polish and insertion
        // consume even when recovery re-recognized the audio.
        if context.live != nil {
            publish(
                TranscriptSnapshot(committed: rawText, tentative: ""),
                for: context.dictationSessionID,
                phase: .locked
            )
        }

        // The keep-or-fall-back decision lives in `Polish.run`, shared with
        // Re-run Polish (ADR-0004): the candidate is already sanitized, so the
        // check judges the transform, not stripped scaffolding, and a fallback
        // keeps `text` at the raw transcript — extending the "model unreachable"
        // fallback to "model answered the wrong question." No new Badge state. The
        // emit here matches `Polish.run`'s gate via `Mode.willPolish`.
        let willPolish = mode.willPolish(text)
        if willPolish, let model = mode.llmModel {
            guard emit(.polishing(model: model)) else { return }
        }
        guard !Task.isCancelled else { return }
        let polishStartedAt = willPolish ? monotonicNow() : nil
        var generationTiming: OllamaGenerationTiming?
        let polished = await Polish.run(rawText: text, mode: mode) { text, mode in
            let result = await self.polish(text, mode)
            generationTiming = result.timing
            return result.text
        }
        let polishFinishedAt = willPolish ? monotonicNow() : nil
        guard !Task.isCancelled else { return }
        text = polished.text
        let isPolished = polished.isPolished
        if let verdict = polished.verdict {
            if verdict.fellBack {
                logOffTaskFallback(verdict, mode: mode)
            }
            Log.pipeline.info("llm: \(text, privacy: .private)")
        }

        // Frontmost app is the paste target, captured just before insertion.
        let serialTailStartedAt = monotonicNow()
        let sourceApp = await frontmostApp()
        guard !Task.isCancelled else { return }
        let insertStartedAt = monotonicNow()
        let pasted = await insert(text)
        let insertFinishedAt = monotonicNow()
        // The insert effect cannot be rolled back once started, but shutdown is
        // terminal: do not publish completion or history after it returns.
        guard !Task.isCancelled else { return }
        guard emit(pasted ? .inserted : .clipboard) else { return }

        let timing = DictationSessionTiming(
            totalMilliseconds: elapsedMilliseconds(from: requestedAt, to: insertFinishedAt),
            queuedMilliseconds: elapsedMilliseconds(
                from: requestedAt, to: processingStartedAt
            ),
            transcribeMilliseconds: elapsedMilliseconds(
                from: transcribeStartedAt, to: transcribeFinishedAt
            ),
            polishMilliseconds: elapsedMilliseconds(
                from: polishStartedAt, to: polishFinishedAt
            ),
            polishServerMilliseconds: generationTiming?.totalMilliseconds,
            polishModelLoadMilliseconds: generationTiming?.modelLoadMilliseconds,
            polishPromptEvalMilliseconds: generationTiming?.promptEvalMilliseconds,
            polishGenerationMilliseconds: generationTiming?.generationMilliseconds,
            insertMilliseconds: elapsedMilliseconds(
                from: insertStartedAt, to: insertFinishedAt
            ),
            serialTailMilliseconds: elapsedMilliseconds(
                from: serialTailStartedAt, to: insertFinishedAt
            )
        )
        logTiming(timing, polishRan: willPolish)

        // Recorded after insertion so a history write can never delay the
        // paste (PRD #78); `record` is best-effort and never breaks a session.
        // Gated on the master switch: with saving off the Pipeline assembles
        // and hands off no entry, so nothing is written to disk.
        guard saveHistory else { return }
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(),
            text: text,
            rawText: rawText,
            isPolished: isPolished,
            modeName: mode.name,
            modeID: mode.id,
            wordCount: text.split(whereSeparator: { $0.isWhitespace }).count,
            sourceApp: sourceApp,
            durationMs: Int(Double(samples.count) / AudioRecorder.sampleRate * 1000),
            flagged: false,
            flagReason: nil,
            timing: timing
        )
        withStateLock {
            guard !isShutDown else { return }
            record(entry)
        }
    }

    private func elapsedMilliseconds(
        from start: Duration?,
        to end: Duration?
    ) -> Double? {
        guard let start, let end else { return nil }
        return elapsedMilliseconds(from: start, to: end)
    }

    private func elapsedMilliseconds(from start: Duration, to end: Duration) -> Double {
        let components = (end - start).components
        let milliseconds = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return max(0, milliseconds)
    }

    private func logTiming(_ timing: DictationSessionTiming, polishRan: Bool) {
        func formatted(_ value: Double?) -> String {
            value.map { String(format: "%.1f", $0) } ?? "n/a"
        }
        Log.dictationPerformance.info("""
        Dictation timing [polish-ran=\(String(polishRan), privacy: .public)] \
        total=\(formatted(timing.totalMilliseconds), privacy: .public)ms \
        queued=\(formatted(timing.queuedMilliseconds), privacy: .public)ms \
        transcribe=\(formatted(timing.transcribeMilliseconds), privacy: .public)ms \
        polish=\(formatted(timing.polishMilliseconds), privacy: .public)ms \
        server=\(formatted(timing.polishServerMilliseconds), privacy: .public)ms \
        load=\(formatted(timing.polishModelLoadMilliseconds), privacy: .public)ms \
        prompt=\(formatted(timing.polishPromptEvalMilliseconds), privacy: .public)ms \
        generate=\(formatted(timing.polishGenerationMilliseconds), privacy: .public)ms \
        insert=\(formatted(timing.insertMilliseconds), privacy: .public)ms \
        serial-tail=\(formatted(timing.serialTailMilliseconds), privacy: .public)ms
        """)
    }

    /// The two points the streaming latency gate reads (PRD #351): how long the
    /// first words took to show, and what finalization cost after release.
    private func logStreamTimings(_ timings: TranscriptStreamTimings) {
        func formatted(_ value: Duration?) -> String {
            guard let value else { return "n/a" }
            return String(format: "%.1f", elapsedMilliseconds(from: .zero, to: value))
        }
        Log.dictationPerformance.info("""
        Streaming timing \
        first-snapshot=\(formatted(timings.timeToFirstSnapshot), privacy: .public)ms \
        finalization=\(formatted(timings.finalization), privacy: .public)ms
        """)
    }

    private func transcribe(
        _ samples: [Float],
        using asrSession: any ASRSessionHandle,
        live: LiveTranscription?
    ) async -> String? {
        defer {
            asrSession.release()
            endLiveTranscription(live)
        }
        guard samples.count >= 1600 else { // < 0.1 s — no real audio captured
            emit(.idle)
            return nil
        }
        // Near-silence makes ASR hallucinate — skip it.
        guard samples.contains(where: { abs($0) >= 0.005 }) else {
            emit(.idle)
            return nil
        }
        do {
            // A streaming session's own stream is the sole authority (ADR-0009):
            // it has already recognized this audio, so there is no second batch
            // transcription to run over the same buffer.
            let text = if let live {
                try await live.resolve(retained: samples)
            } else {
                try await asrSession.transcribe(samples)
            }
            if let timings = live?.timings {
                logStreamTimings(timings)
            }
            guard !Task.isCancelled else { return nil }
            return text
        } catch is CancellationError {
            guard !Task.isCancelled else { return nil }
            emit(.idle)
            return nil
        } catch {
            Log.pipeline.error(
                "Transcription failed: \(String(describing: error), privacy: .public)"
            )
            emit(.error("\(error)"))
            return nil
        }
    }

    /// One public-level line per off-task fallback, for tuning thresholds from
    /// field behavior: the signal that fired plus the numeric overlap and
    /// length ratio, never the discarded output or the transcript (those stay
    /// on the `.private` "llm:"/"raw:" lines).
    private func logOffTaskFallback(_ verdict: OllamaClient.OffTaskVerdict, mode: Mode) {
        let overlap = String(format: "%.2f", verdict.overlap)
        let ratio = String(format: "%.2f", verdict.lengthRatio)
        Log.pipeline.error("""
        Polish off-task (\(verdict.signal, privacy: .public)) in mode \
        \(mode.name, privacy: .public) [expands=\(String(mode.expands), privacy: .public)] — \
        overlap \(overlap, privacy: .public), length ratio \(ratio, privacy: .public); \
        pasting raw transcript
        """)
    }
}
