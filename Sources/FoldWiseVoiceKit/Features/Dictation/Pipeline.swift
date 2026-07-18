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
}

/// A Dictation session's captured transcription capability. Pipeline can use
/// and release it without learning which model or engine the lifecycle owns.
protocol ASRSessionHandle: AnyObject {
    func transcribe(_ samples: [Float]) async throws -> String
    func release()
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

final class Pipeline {
    private struct RecordingContext {
        let mode: Mode
        let asrSession: any ASRSessionHandle
    }

    let config: Config

    private let recorder: AudioRecording
    private let sessionProvider: ASRSessionHandleProviding
    private let ducker: AudioDucking
    private let polish: (String, Mode) async -> String
    private let insert: (String) async -> Bool
    /// Best-effort history sink (PRD #78): handed the assembled entry after
    /// insertion. A closure seam mirroring `polish`/`insert` (ADR-0002).
    private let record: (HistoryEntry) -> Void
    /// Frontmost-app name at insert time. Injectable so tests stay AppKit-free.
    private let frontmostApp: () async -> String?

    /// Recursive because state observers and injected effects may synchronously
    /// call back into the Pipeline. State delivery stays inside the lock so a
    /// callback accepted before shutdown cannot arrive after terminal idle.
    private let stateLock = NSRecursiveLock()

    /// May fire from any thread — UIs must hop to the main thread themselves.
    var onState: ((PipelineState) -> Void)?

    /// Owned here rather than read back through the record seam, so the
    /// start/stop guards are self-contained and fakes needn't track it.
    private var recording = false
    private var recordingContext: RecordingContext?
    private var lastJob: Task<Void, Never>?
    private var jobActive = false
    private var lastEmitted: PipelineState = .idle
    private var isShutDown = false

    init(
        config: Config,
        recorder: AudioRecording,
        sessionProvider: ASRSessionHandleProviding,
        ducker: AudioDucking = AudioDucker(),
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish,
        insert: @escaping (String) async -> Bool = Pipeline.pasteboardInsert,
        record: @escaping (HistoryEntry) -> Void = Pipeline.recordToHistory,
        frontmostApp: @escaping () async -> String? = Pipeline.frontmostAppName
    ) {
        self.config = config
        self.recorder = recorder
        self.sessionProvider = sessionProvider
        self.ducker = ducker
        self.polish = polish
        self.insert = insert
        self.record = record
        self.frontmostApp = frontmostApp
        self.recorder.onFailure = { [weak self] error in
            self?.recordingFailed(error)
        }
    }

    // MARK: - production stage defaults

    static func ollamaPolish(_ text: String, mode: Mode) async -> String {
        guard let model = mode.llmModel else { return text }
        return await OllamaClient.polish(
            text, model: model, systemPrompt: mode.systemPrompt, vocab: mode.vocab,
            expands: mode.expands
        )
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
        withStateLock {
            guard !isShutDown, !recording, !sessionProvider.isDictationBlocked else { return }
            let asrSession: any ASRSessionHandle
            do {
                asrSession = try sessionProvider.captureSession()
            } catch {
                Log.pipeline.error(
                    "ASR session capture skipped: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
            if config.pauseAudio { ducker.duck() }
            recording = true
            let mode = config.mode
            do {
                try recorder.start()
                recordingContext = RecordingContext(mode: mode, asrSession: asrSession)
                emit(.listening(mode: mode.name))
            } catch {
                recording = false
                asrSession.release()
                ducker.restore()
                emit(.error(error.localizedDescription))
            }
        }
    }

    func stopRecording() {
        withStateLock {
            guard !isShutDown, recording else { return }
            recording = false
            let samples = recorder.stop()
            ducker.restore()
            guard let context = recordingContext else { return }
            recordingContext = nil
            let asrSession = context.asrSession
            guard emit(.transcribing) else {
                asrSession.release()
                return
            }
            // Unlike the start-time Mode snapshot, whether this session is saved is
            // decided when the user stops speaking, not read later off the job task.
            let saveHistory = config.saveHistory
            let previous = lastJob
            lastJob = Task {
                await withTaskCancellationHandler {
                    await previous?.value
                    guard !Task.isCancelled else {
                        asrSession.release()
                        return
                    }
                    await self.process(
                        samples,
                        mode: context.mode,
                        asrSession: asrSession,
                        saveHistory: saveHistory
                    )
                } onCancel: {
                    previous?.cancel()
                }
            }
        }
    }

    func toggleRecording() {
        withStateLock {
            guard !isShutDown else { return }
            if recording {
                stopRecording()
            } else {
                startRecording()
            }
        }
    }

    /// Test hook: awaits the most recently queued session job. Each job
    /// awaits its predecessor, so this drains the whole chain.
    func awaitPendingJob() async {
        let pendingJob = withStateLock { lastJob }
        await pendingJob?.value
    }

    func shutdown() {
        withStateLock {
            guard !isShutDown else { return }
            isShutDown = true
            recording = false
            releaseRecordingContext()
            lastJob?.cancel()
            ducker.restore()
            recorder.close()
            deliver(.idle)
        }
    }

    private func recordingFailed(_ error: AudioCaptureError) {
        withStateLock {
            guard !isShutDown, recording else { return }
            recording = false
            releaseRecordingContext()
            ducker.restore()
            emit(.error(error.localizedDescription))
        }
    }

    private func releaseRecordingContext() {
        recordingContext?.asrSession.release()
        recordingContext = nil
    }

    // MARK: - worker

    private func process(
        _ samples: [Float],
        mode: Mode,
        asrSession: any ASRSessionHandle,
        saveHistory: Bool
    ) async {
        let started = withStateLock {
            guard !isShutDown else { return false }
            jobActive = true
            return true
        }
        guard started else {
            asrSession.release()
            return
        }
        defer { withStateLock { jobActive = false } }
        guard var text = await transcribe(samples, using: asrSession) else { return }
        guard !text.isEmpty else {
            emit(.idle)
            return
        }
        Log.pipeline.info("raw: \(text, privacy: .private)")
        let rawText = text

        // The keep-or-fall-back decision lives in `Polish.run`, shared with
        // Re-run Polish (ADR-0004): the candidate is already sanitized, so the
        // check judges the transform, not stripped scaffolding, and a fallback
        // keeps `text` at the raw transcript — extending the "model unreachable"
        // fallback to "model answered the wrong question." No new Badge state. The
        // emit here matches `Polish.run`'s gate via `Mode.willPolish`.
        if mode.willPolish(text), let model = mode.llmModel {
            guard emit(.polishing(model: model)) else { return }
        }
        guard !Task.isCancelled else { return }
        let polished = await Polish.run(rawText: text, mode: mode, polish: polish)
        guard !Task.isCancelled else { return }
        text = polished.text
        let isPolished = polished.isPolished
        if let verdict = polished.verdict {
            if verdict.fellBack { logOffTaskFallback(verdict, mode: mode) }
            Log.pipeline.info("llm: \(text, privacy: .private)")
        }

        // Frontmost app is the paste target, captured just before insertion.
        let sourceApp = await frontmostApp()
        guard !Task.isCancelled else { return }
        let pasted = await insert(text)
        // The insert effect cannot be rolled back once started, but shutdown is
        // terminal: do not publish completion or history after it returns.
        guard !Task.isCancelled else { return }
        guard emit(pasted ? .inserted : .clipboard) else { return }

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
            flagReason: nil
        )
        withStateLock {
            guard !isShutDown else { return }
            record(entry)
        }
    }

    private func transcribe(
        _ samples: [Float],
        using asrSession: any ASRSessionHandle
    ) async -> String? {
        defer { asrSession.release() }
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
            let text = try await asrSession.transcribe(samples)
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
